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
    sharedPage = await browser.newPage();
    await openLeanNotebook(sharedPage);
  });

  test.afterAll(async () => {
    await sharedPage?.close();
  });

  test('#eval (1+1) returns 2', async () => {
    const output = await runCell(sharedPage, '#eval (1+1)');
    await expect(output).toContainText('2');
  });

  test('#html renders raw HTML', async () => {
    const output = await runCell(
      sharedPage,
      '#html "<b data-e2e=\\"marker\\">bold text</b>"'
    );
    // Check for the rendered HTML content
    await expect(output).toContainText('bold text');
  });

  test('#latex renders via MathJax', async () => {
    const output = await runCell(
      sharedPage,
      String.raw`#latex "\\int_0^1 x^2 \\, dx = \\frac{1}{3}"`
    );
    await expect(
      output.locator('mjx-container, .MathJax, .jp-RenderedLatex')
    ).toBeVisible();
  });

  test('#svg embeds an SVG', async () => {
    const output = await runCell(
      sharedPage,
      String.raw`#svg "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"40\" height=\"40\"><circle cx=\"20\" cy=\"20\" r=\"18\" fill=\"red\"/></svg>"`
    );
    // SVG may be rendered inline or wrapped in an <img> tag depending
    // on JupyterLab's MIME renderer. Accept either form.
    await expect(output.locator('svg, img')).toBeVisible();
  });

  test('#md renders Markdown', async () => {
    const output = await runCell(
      sharedPage,
      String.raw`#md "# Title\n\n**bold** text"`
    );
    await expect(output).toContainText('Title');
  });
});
