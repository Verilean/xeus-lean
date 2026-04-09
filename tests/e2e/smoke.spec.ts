import { test, expect } from '@playwright/test';

/**
 * Phase 1 smoke test: make sure the JupyterLite Lab UI actually loads
 * from the locally-built _output/. Nothing about the xlean kernel is
 * exercised here — this just proves the test harness, HTTP server,
 * Playwright, and the static site are all talking to each other.
 */
test('JupyterLite Lab UI loads', async ({ page }) => {
  // Occasional "ServiceWorker was already registered" warnings are
  // harmless; only fail on actual errors.
  const errors: string[] = [];
  page.on('pageerror', (err) => errors.push(err.message));

  await page.goto('/lab/index.html');

  // The main shell class JupyterLab ships is stable across versions.
  // Use `.first()` because `#main` and `.jp-LabShell` can land on the
  // same element (strict-mode violation otherwise).
  await expect(
    page.locator('#main, .jp-LabShell, #jp-main-dock-panel').first()
  ).toBeVisible({ timeout: 60_000 });

  // Title should settle on something like "JupyterLab" or "JupyterLite".
  await expect(page).toHaveTitle(/Jupyter/i, { timeout: 30_000 });

  expect(errors, `page errors: ${errors.join('\n')}`).toEqual([]);
});
