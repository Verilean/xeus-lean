/**
 * Helpers for driving a JupyterLab (JupyterLite) session from
 * Playwright. The goal is to hide the messy DOM details and the
 * long waits behind a handful of intent-level functions:
 *
 *     await openLeanNotebook(page);
 *     const out = await runCell(page, '#html "<b>hi</b>"');
 *     const dom = await dumpOutputJson(page, out);
 *
 * All timeouts are deliberately generous because the xlean kernel
 * loads a ~480MB WASM module on first use.
 */

import { Page, Locator, expect } from '@playwright/test';
import { browserSerializer, buildOptions, SerializeOptions } from './dom-serialize';

const KERNEL_BOOT_TIMEOUT = 300_000;
// Cells that hit `import` paths (and therefore a fresh
// `processInput` → `processHeader` → `importModulesCore`) can take
// 30-60 s on the GitHub Actions runner where memory pressure from
// the loaded Std/Lean/Sparkle/Hesper olean trees hurts kernel
// throughput. Locally the same cells finish in 1-2 s, but in CI we
// have seen `#latex` exceed 60 s. Three minutes is generous enough
// to absorb that without masking real hangs.
const CELL_EXEC_TIMEOUT = 180_000;

/**
 * Launch a fresh notebook backed by the xlean kernel.
 *
 * We open the shipped `notebooks/rich-display.ipynb` directly via
 * JupyterLab's tree URL. That notebook declares the xlean kernelspec
 * in its metadata, so the kernel is selected automatically with no
 * modal to dismiss — avoiding fragile menu / command-palette DOM
 * interactions.
 *
 * Tests that need an empty cell should use `clearAndReplaceCell`
 * on the first code cell in the notebook, which `runCell` does
 * implicitly.
 */
export async function openLeanNotebook(
  page: Page,
  notebook: string = 'rich-display.ipynb'
): Promise<void> {
  // JupyterLite is a SPA, so deep-linking uses a query param rather
  // than a /lab/tree/... path (the static HTTP server doesn't know
  // about /tree/). `path=` tells the client-side router which file
  // to open after the shell mounts.
  await page.goto(`/lab/index.html?path=${notebook}`);

  // Wait until the main shell exists.
  await page.locator('#jp-main-dock-panel, .jp-LabShell').first().waitFor({
    state: 'visible',
    timeout: 60_000,
  });

  // Occasionally a "Select Kernel" modal still appears (e.g. if the
  // preferred kernel can't be auto-matched). Dismiss it if present.
  const modal = page.locator('.jp-Dialog, dialog[aria-modal="true"]').first();
  if (await modal.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await modal.getByRole('button', { name: 'Select Kernel', exact: true }).click();
    await modal.waitFor({ state: 'hidden', timeout: 10_000 });
  }

  // Wait for the notebook DOM and the first code cell.
  await page.locator('.jp-Notebook').waitFor({ state: 'visible', timeout: 30_000 });
  await page.locator('.jp-Notebook .jp-CodeCell').first().waitFor({
    state: 'visible',
    timeout: 30_000,
  });

  // Wait for the kernel to reach "idle". JupyterLab surfaces this as
  // an aria-label like "Kernel status: Idle" on the status bar.
  await waitForKernelIdle(page);
}

/** Wait until the kernel status indicator reports idle. */
export async function waitForKernelIdle(page: Page): Promise<void> {
  // JupyterLab surfaces kernel status in different places depending
  // on the version. The most reliable indicator in JupyterLab 4 /
  // JupyterLite 0.7 is a status-bar button labelled "Lean 4 | Idle".
  // We also keep legacy selectors as fallbacks.
  const idle = page
    .locator(
      [
        // JupyterLab 4 / JupyterLite: status bar button "Lean 4 | Idle"
        'button:has-text("Idle")',
        // Notebook execution indicator
        '.jp-Notebook-ExecutionIndicator[data-status="idle"]',
        // Older JupyterLab: aria-label on status icon
        '[aria-label*="Kernel status: Idle" i]',
      ].join(', ')
    )
    .first();

  await idle.waitFor({ state: 'visible', timeout: KERNEL_BOOT_TIMEOUT });
}

/**
 * Type the given source into the first (or most recently added) code
 * cell and run it with Shift+Enter. Returns a locator pointing at
 * that cell's output area, once the output has appeared.
 */
export async function runCell(page: Page, source: string): Promise<Locator> {
  // Find the *last* code cell in the notebook — this is where new
  // cells land after the previous Shift+Enter.
  const cells = page.locator('.jp-Notebook .jp-CodeCell');
  const count = await cells.count();
  expect(count, 'expected at least one code cell').toBeGreaterThan(0);
  const cell = cells.nth(count - 1);

  // Focus the CodeMirror editor and select-all + replace.
  const editor = cell.locator('.cm-content').first();
  await editor.click();
  await page.keyboard.press('Control+A');
  await page.keyboard.press('Delete');
  // Type the source literally. CodeMirror is fine with this.
  await page.keyboard.type(source, { delay: 0 });

  // Execute.
  await page.keyboard.press('Shift+Enter');

  // Wait for the output area under the just-run cell.
  const output = cell.locator('.jp-OutputArea-output').first();
  await output.waitFor({ state: 'visible', timeout: CELL_EXEC_TIMEOUT });

  // Wait for kernel to go idle again before moving on.
  await waitForKernelIdle(page);
  return output;
}

/**
 * Serialize the given element (or selector) inside the page to a
 * normalized JSON object suitable for snapshot comparison.
 */
export async function dumpDomJson(
  page: Page,
  target: Locator | string,
  options?: SerializeOptions
): Promise<unknown> {
  const opts = buildOptions(options);

  // Resolve to a stable selector string so the browser-side function
  // can re-query the DOM. If we were given a Locator, ask Playwright
  // for its internal selector via `evaluate` + a bit of hackery: the
  // simplest is to mark the target element with a temporary
  // data-attribute, read it by that, then clean up.
  if (typeof target === 'string') {
    return await page.evaluate(
      ([fn, sel, o]) => {
        // eslint-disable-next-line no-eval
        const f = eval(`(${fn})`);
        return f(sel, o);
      },
      [browserSerializer.toString(), target, opts] as const
    );
  }

  const TAG = '__xeus_lean_snap__';
  await target.evaluate((el, tag) => el.setAttribute(tag, '1'), TAG);
  try {
    return await page.evaluate(
      ([fn, sel, o]) => {
        // eslint-disable-next-line no-eval
        const f = eval(`(${fn})`);
        return f(sel, o);
      },
      [browserSerializer.toString(), `[${TAG}]`, opts] as const
    );
  } finally {
    await target
      .evaluate((el, tag) => el.removeAttribute(tag), TAG)
      .catch(() => {});
  }
}
