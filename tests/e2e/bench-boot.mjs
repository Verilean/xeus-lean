// Benchmark xlean's JupyterLite boot time and memory footprint.
//
// Usage:
//   node bench-boot.mjs http://127.0.0.1:8765 [cold|warm]
//
//   cold (default): fresh browser context, IndexedDB empty.
//   warm:           prime IDB with a first run, then time a second
//                   run that reuses the same persistent context.
//
// Reports JSON to stdout so a CI workflow can parse it:
//   { "boot_ms": …, "kernel_idle_ms": …, "js_heap_mb": … }
//
import { chromium } from 'playwright';

const BASE = process.argv[2] ?? 'http://127.0.0.1:8765';
const MODE = process.argv[3] ?? 'cold';
if (!['cold', 'warm'].includes(MODE)) {
  console.error(`unknown mode: ${MODE}`);
  process.exit(2);
}

// For warm runs we need a persistent context so IDB survives the
// first navigation.  Playwright's launchPersistentContext gives us
// that with a tmp profile directory.
import { mkdtempSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';

const profileDir = mkdtempSync(join(tmpdir(), 'xlean-bench-'));
let ctx, browser;
if (MODE === 'cold') {
  browser = await chromium.launch({ headless: true });
  ctx = await browser.newContext({ viewport: { width: 1100, height: 700 } });
} else {
  ctx = await chromium.launchPersistentContext(profileDir, {
    headless: true,
    viewport: { width: 1100, height: 700 },
  });
}

// `result` is the structured benchmark output for the *measured*
// run (the second run in warm mode, the only run in cold mode).
let result = {};

async function timedBoot(page) {
  const t0 = Date.now();
  await page.goto(`${BASE}/lab/index.html?path=rich-display.ipynb`, { timeout: 180_000 });
  // Wait until the shell is up...
  await page.locator('#jp-main-dock-panel, .jp-LabShell').first()
    .waitFor({ state: 'visible', timeout: 120_000 });
  await page.locator('.jp-Notebook .jp-CodeCell').first()
    .waitFor({ state: 'visible', timeout: 120_000 });
  const tShell = Date.now() - t0;

  // ...then wait until the kernel reports Idle (post.js olean load
  // is over by then because addRunDependency blocks Wasm main).
  const idle = page.locator(
    'button:has-text("Idle"), .jp-Notebook-ExecutionIndicator[data-status="idle"]'
  ).first();
  await idle.waitFor({ state: 'visible', timeout: 300_000 });
  const tIdle = Date.now() - t0;

  // Read JS heap (Chromium only).
  const heap = await page.evaluate(() => {
    if (performance && performance.memory) {
      return {
        used:   performance.memory.usedJSHeapSize,
        total:  performance.memory.totalJSHeapSize,
        limit:  performance.memory.jsHeapSizeLimit,
      };
    }
    return null;
  });
  return { shellMs: tShell, idleMs: tIdle, heap };
}

if (MODE === 'warm') {
  // First run: populate IDB.  Don't time this; just wait for it
  // to land.
  const primePage = await ctx.newPage();
  await timedBoot(primePage);
  await primePage.close();
}

const page = await ctx.newPage();
const r = await timedBoot(page);
result = {
  mode: MODE,
  shell_ms: r.shellMs,
  kernel_idle_ms: r.idleMs,
  js_heap_used_mb: r.heap ? Math.round(r.heap.used / 1024 / 1024) : null,
  js_heap_total_mb: r.heap ? Math.round(r.heap.total / 1024 / 1024) : null,
};

console.log(JSON.stringify(result, null, 2));

await page.close();
await ctx.close();
if (browser) await browser.close();
try { rmSync(profileDir, { recursive: true, force: true }); } catch {}
