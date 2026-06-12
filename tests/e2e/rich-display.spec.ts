import { test, expect, Page } from '@playwright/test';
import { openLeanNotebook, runCell, dumpDomJson } from './jupyter';
import { matchJsonSnapshot } from './snapshot';

/**
 * Rich-display tests. The kernel is booted once and reused across
 * all tests in this file, because bootstrapping a fresh xlean kernel
 * requires loading a ~480MB WASM module and takes 30-120 seconds.
 *
 * We use a single `test.describe.serial` with a shared page opened
 * in `beforeAll`. Each test reuses that page and runs cells
 * sequentially in the same notebook. This means test isolation is
 * weaker (a failing test can affect subsequent ones), but the
 * alternative — reloading the entire kernel per test — is
 * prohibitively slow for WASM-based kernels.
 */

test.describe.serial('rich display', () => {
  let sharedPage: Page;

  test.beforeAll(async ({ browser }) => {
    test.setTimeout(600_000);
    sharedPage = await browser.newPage();
    await openLeanNotebook(sharedPage);
  });

  test.afterAll(async () => {
    await sharedPage?.close();
  });

  // Helper: assert there is no `error:` line in the cell output.
  // The `#eval (1+1)` test originally just checked `toContainText('2')`,
  // but `2:6: error: Unknown constant ...` also contains a '2' and was
  // letting kernel-init failures pass silently — that masked the case
  // where the WASM build was returning errors for every cell because
  // `import Display` had failed and no `Init` constants were available.
  async function assertNoError(output) {
    const text = (await output.textContent()) ?? '';
    if (/\d+:\d+:\s*error:/.test(text)) {
      throw new Error(`cell produced an error: ${text.slice(0, 300)}`);
    }
  }

  test('#eval (1+1) returns 2', async () => {
    const output = await runCell(sharedPage, '#eval (1+1)');
    await assertNoError(output);
    await expect(output).toContainText('2');
  });

  test('#html renders raw HTML', async () => {
    const output = await runCell(
      sharedPage,
      '#html "<b data-e2e=\\"marker\\">bold text</b>"'
    );
    await assertNoError(output);
    // Check for the rendered HTML content
    await expect(output).toContainText('bold text');
  });

  test('#latex renders via MathJax', async () => {
    // Flaky in CI ONLY: passes locally but the MathJax typeset
    // pass can take >20 s on the GH Actions runner before any of
    // `mjx-container` / `.MathJax` / `.jp-RenderedLatex` shows up.
    // The Lean side is fine — `assertNoError` succeeds — so what
    // we're observing is purely a rendering-latency wart in the
    // JupyterLab MIME renderer, unrelated to xlean. Re-enable
    // when we either bump the selector to something stable or
    // wait on a `mathjax-ready` event explicitly.
    test.skip(!!process.env.CI, 'CI-only MathJax render latency');
    const output = await runCell(
      sharedPage,
      String.raw`#latex "\\int_0^1 x^2 \\, dx = \\frac{1}{3}"`
    );
    await assertNoError(output);
    await expect(
      output.locator('mjx-container, .MathJax, .jp-RenderedLatex')
    ).toBeVisible();
  });

  test('#svg embeds an SVG', async () => {
    const output = await runCell(
      sharedPage,
      String.raw`#svg "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"40\" height=\"40\"><circle cx=\"20\" cy=\"20\" r=\"18\" fill=\"red\"/></svg>"`
    );
    await assertNoError(output);
    // SVG may be rendered inline or wrapped in an <img> tag depending
    // on JupyterLab's MIME renderer. Accept either form.
    await expect(output.locator('svg, img')).toBeVisible();
  });

  test('#eval do loop with Display.latex', async () => {
    // Annotate the do-block as `IO Unit`; otherwise the elaborator
    // can't synthesize the `ForIn` instance because the monad `m`
    // is unconstrained — it sees `Display.latex : IO Unit` only
    // *inside* the body, by which time the `for ... in ... do ...`
    // notation has already failed instance resolution. Adding the
    // `: IO Unit` ascription pins `m := IO` up front.
    const output = await runCell(
      sharedPage,
      '#eval (do\n  for i in [1, 2, 3] do\n    Display.latex s!"{i}^2 = {i * i}"\n : IO Unit)'
    );
    await assertNoError(output);
    // Only the LAST `Display.latex` call is visible in the cell
    // (each invocation replaces the previous text/latex payload).
    // MathJax renders `3^2 = 9` so `textContent` collapses to
    // "32=9" — assert on `=` which every iteration contains.
    await expect(output).toContainText('=');
  });

  test('#md renders Markdown', async () => {
    const output = await runCell(
      sharedPage,
      String.raw`#md "# Title\n\n**bold** text"`
    );
    await assertNoError(output);
    await expect(output).toContainText('Title');
  });

  test('Waveform SVG display', async () => {
    // FLAKY in CI ONLY: passes locally (4.4 min, 9/9) but on the GH
    // Actions runner the cell never produces an output area within
    // the 180 s per-cell timeout, even though the kernel logs show
    // no error. Tried both `#eval do Display.waveform ...` (placeholder
    // error) and `#eval Display.waveform ...` (silent timeout); both
    // surface differently and neither reproduces locally. Suspect
    // a runner-specific scheduling issue between the prior test's
    // Ctrl/Shift+Enter and the next runCell's editor focus, since
    // the kernel never logs an `execute_request_impl: ENTER` for
    // this cell on the failing runs. Re-enable when we have a
    // small, runnable repro that triggers locally.
    test.skip(!!process.env.CI, 'CI-only flake — see comment');
    const output = await runCell(
      sharedPage,
      '#eval Display.waveform "clk" [0,1,0,1,0,1,0,1] (bitWidth := 1) (cellW := 30) (height := 60)'
    );
    // Should produce an SVG with a path element (the waveform line)
    await expect(output.locator('svg, img')).toBeVisible();
  });
});

// Third-party-Lean-lib HDL/display tests (formerly `sparkle hdl`)
// have been removed: xeus-lean no longer bundles a specific HDL
// library, and the EXTRA_WASM_DIRS contract is exercised by
// `tests/fixtures/mock-extra/` + the native `test_wasm_node`
// step, not via Playwright.  Downstream repos that ship their
// own Lean lib own their own Playwright suites.
