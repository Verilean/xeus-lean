import { defineConfig, devices } from '@playwright/test';
import * as path from 'path';

/**
 * Playwright config for xeus-lean end-to-end tests.
 *
 * The tests require a pre-built JupyterLite site at ../../../_output/.
 * If that directory is missing, build it with the usual pixi-based WASM
 * build (`make deploy` or the CI steps). Playwright will not build it
 * for you — the WASM toolchain is too heavy for a test-runner bootstrap.
 *
 * We launch a tiny HTTP server on OUTPUT_PORT (default 8765) via the
 * `webServer` option below, and each test navigates to it through
 * `baseURL`.
 */

const OUTPUT_DIR = path.resolve(__dirname, '../../_output');
const OUTPUT_PORT = Number(process.env.XEUS_LEAN_E2E_PORT ?? 8765);

export default defineConfig({
  testDir: __dirname,
  testMatch: /.*\.spec\.ts/,

  // WASM load + Lean init is slow on first open; give each test plenty
  // of headroom. Individual awaits still use tighter timeouts where
  // possible so failures surface as readable errors rather than
  // whole-test timeouts.
  timeout: 180_000,
  expect: {
    timeout: 20_000,
  },

  // The WASM kernel is single-threaded and heavy (~480MB), so parallel
  // execution is a bad idea: it just thrashes memory. Force serial.
  fullyParallel: false,
  workers: 1,

  reporter: [
    ['list'],
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
  ],

  use: {
    baseURL: `http://127.0.0.1:${OUTPUT_PORT}`,
    // JupyterLite uses a service worker and local storage aggressively;
    // Playwright's default is a fresh context per test, which is what
    // we want to avoid stale kernel state leaking between tests.
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'off',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  webServer: {
    // Requires Python 3 — already present in the dev shell (shell.nix).
    command: `python3 -m http.server ${OUTPUT_PORT} --bind 127.0.0.1 --directory ${OUTPUT_DIR}`,
    url: `http://127.0.0.1:${OUTPUT_PORT}/lab/index.html`,
    timeout: 60_000,
    reuseExistingServer: !process.env.CI,
    stdout: 'ignore',
    stderr: 'pipe',
  },
});
