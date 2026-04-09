# xeus-lean end-to-end tests

Playwright-driven browser tests for the JupyterLite deployment.

## Requirements

- **A pre-built `_output/`** at the repo root. The WASM toolchain is
  heavy, so Playwright intentionally does *not* build it for you. Run
  the normal pixi-based build first (see the root `README.md` /
  `Makefile` for `make deploy` or the individual steps).
- **Node.js 23+** — already in `shell.nix`.
- **Chromium** — installed by `npm run install-browsers`.

## Setup

```bash
cd tests/e2e
npm install
npm run install-browsers
```

## Running

```bash
# headless, standard run
npm test

# interactive UI mode (great for writing new tests / debugging)
npm run test:ui

# headed (visible) browser, useful for step-debugging
npm run test:headed

# regenerate JSON DOM snapshots after an intentional change
npm run test:update
```

The harness launches `python3 -m http.server` on port 8765 pointed at
`_output/`, so make sure that port is free (override with the
`XEUS_LEAN_E2E_PORT` env var).

## Snapshot strategy

Output DOM is dumped to JSON (not PNG), with volatile attributes —
random IDs, MathJax inline styles, etc. — stripped out by
`dom-serialize.ts`. Committed snapshots live in `__snapshots__/*.json`,
one file per test. Diffs are reviewable with `git diff`.

To intentionally update a snapshot: fix the code, run
`npm run test:update`, eyeball the diff, then commit.
