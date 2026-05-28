// Headless profile of an xlean boot.
//
// Usage:
//   node bench-profile.mjs http://127.0.0.1:8765 [cold|warm]
//
// Cold: fresh context, IDB + Cache empty.
// Warm: persistent context with a previous boot already cached.
//
// Reports:
//   * Resource Timing for every network request the page made
//     (URL, transferSize, duration).
//   * Long Tasks (> 50 ms) — synchronous work that blocks the
//     main worker / kernel thread.  This is where the boot stalls
//     for "WASM compile" / "FS.writeFile loop" / "Lean init" etc.
//   * Console messages from post.js (already timestamped if a
//     newer build is loaded).
//   * Three high-level milestones: shell visible / kernel idle /
//     test #eval prompt accepted.
//
// Output is JSON to stdout so it's easy to diff.
import { chromium } from 'playwright';
import { mkdtempSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';

const BASE = process.argv[2] ?? 'http://127.0.0.1:8765';
const MODE = process.argv[3] ?? 'cold';

const profileDir = mkdtempSync(join(tmpdir(), 'xlean-profile-'));

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

const consoleLog = [];

async function profileOne(page) {
  // Install a PerformanceObserver as early as we can so long-tasks
  // from boot are captured.
  await page.addInitScript(() => {
    window.__xleanProfile = { longTasks: [], marks: [] };
    try {
      const obs = new PerformanceObserver((list) => {
        for (const e of list.getEntries()) {
          window.__xleanProfile.longTasks.push({
            name: e.name, start: Math.round(e.startTime), duration: Math.round(e.duration),
          });
        }
      });
      obs.observe({ entryTypes: ['longtask'] });
    } catch (_) {}
  });

  page.on('console', (m) => {
    consoleLog.push(`[${m.type()}] ${m.text()}`);
  });

  const t0 = Date.now();
  await page.goto(`${BASE}/lab/index.html?path=rich-display.ipynb`, { timeout: 180_000 });
  await page.locator('#jp-main-dock-panel, .jp-LabShell').first()
    .waitFor({ state: 'visible', timeout: 120_000 });
  await page.locator('.jp-Notebook .jp-CodeCell').first()
    .waitFor({ state: 'visible', timeout: 120_000 });
  const tShell = Date.now() - t0;

  const idle = page.locator(
    'button:has-text("Idle"), .jp-Notebook-ExecutionIndicator[data-status="idle"]'
  ).first();
  await idle.waitFor({ state: 'visible', timeout: 300_000 });
  const tIdle = Date.now() - t0;

  // Pull resource timing + long tasks back into Node.
  const data = await page.evaluate(() => {
    const resources = performance.getEntriesByType('resource')
      .map((r) => ({
        name: r.name,
        type: r.initiatorType,
        transfer: Math.round(r.transferSize),
        duration: Math.round(r.duration),
        start: Math.round(r.startTime),
      }))
      .sort((a, b) => b.duration - a.duration)
      .slice(0, 25);
    const nav = performance.getEntriesByType('navigation')[0] || null;
    return {
      resources,
      longTasks: (window.__xleanProfile?.longTasks || [])
        .sort((a, b) => b.duration - a.duration).slice(0, 15),
      navigation: nav && {
        domContentLoaded: Math.round(nav.domContentLoadedEventEnd),
        loadEvent: Math.round(nav.loadEventEnd),
      },
      memory: performance.memory && {
        usedMB: Math.round(performance.memory.usedJSHeapSize / 1024 / 1024),
        totalMB: Math.round(performance.memory.totalJSHeapSize / 1024 / 1024),
      },
    };
  });

  return { shell_ms: tShell, kernel_idle_ms: tIdle, ...data };
}

if (MODE === 'warm') {
  const prime = await ctx.newPage();
  await profileOne(prime);
  await prime.close();
  // Reset console capture between runs so the warm sample is clean.
  consoleLog.length = 0;
}

const page = await ctx.newPage();
const result = await profileOne(page);

console.log(JSON.stringify({
  mode: MODE,
  ...result,
  // Last 40 olean / WASM-related lines from the worker console so
  // we can see where post.js milestones land.
  console: consoleLog.filter((l) =>
    /\[olean|\[WASM|fzstd|Memory|kernel|Module|exception/i.test(l)
  ).slice(-40),
}, null, 2));

await page.close();
await ctx.close();
if (browser) await browser.close();
try { rmSync(profileDir, { recursive: true, force: true }); } catch {}
