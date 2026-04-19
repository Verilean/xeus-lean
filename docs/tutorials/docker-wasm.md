# WASM build via Docker (30 minutes)

Builds the same JupyterLite site that's deployed to GitHub Pages,
end-to-end inside Docker. Useful when you want to:

- Customize what gets bundled (different `Std` subset, your own
  Lean library, etc.)
- Verify a CI failure locally
- Host xeus-lean on your own server / static CDN

The image is large (~18 GB) because emscripten ships its own LLVM
toolchain and the build keeps a full lake4 stage0 cache.

## Prerequisites

- Docker
- ~25 GB free disk
- The Hesper submodule initialized:

  ```bash
  git submodule update --init --recursive
  ```

## Step 1 — Build the image

From the repo root:

```bash
docker build -f Dockerfile.wasm -t xeus-lean-wasm .
```

What this does (annotated):

| Stage | What | Time |
|-------|------|-----:|
| 1 | Pull `prefix-dev/pixi` base image | ~30 s |
| 2 | Install elan + Lean 4.28-rc1 + Node 23 | ~2 min |
| 3 | `pixi install -e wasm-build` (downloads emscripten) | ~5 min |
| 4 | `lake build REPL Display WasmRepl` | ~3 min |
| 5 | `lake build SparkleDemo` | ~2 min |
| 6 | `bash hesper-wasm/build-wasm.sh ...` (Hesper WGSL) | ~1 min |
| 7 | `emcmake cmake` configure | ~3 min |
| 8 | `emmake make xlean test_wasm_node` (the heavy one) | ~12 min |
| 9 | `cmake --install` + `jupyter lite build` | ~3 min |
| 10 | `pack-olean-modules.sh` (Std/Lean/Sparkle/Hesper → zstd) | ~1 min |

Total: ~30 minutes of CPU plus disk wait.

## Step 2 — Serve the site

The image's default `CMD` runs a tiny Python HTTP server on port 8888:

```bash
docker run --rm -it -p 8888:8888 xeus-lean-wasm
```

Open <http://localhost:8888/lab/> in your browser. JupyterLite mounts
the bundled `notebooks/`. The kernel boots in ~30 s on first load.

## Step 3 — Inspect the output

If you want the static `_output/` on your host (e.g. to push it to a
different web host):

```bash
docker create --name xeus-lean-tmp xeus-lean-wasm
docker cp xeus-lean-tmp:/app/dist ./dist
docker rm xeus-lean-tmp

# Now ./dist is a self-contained static site. Drop it on any
# CDN / GitHub Pages / netlify / your own nginx.
du -sh dist  # ~850 MB
```

## Customizing what gets bundled

### Different upstream Lean

The toolchain is pinned in `lean-toolchain` (used by `lake`) and
echoed by `hesper-wasm/build-wasm.sh`. Edit both, then rebuild:

```bash
echo 'leanprover/lean4:v4.30.0' > lean-toolchain
docker build -f Dockerfile.wasm -t xeus-lean-wasm-4.30 .
```

(The Hesper patch in `hesper-wasm/patches/0001-…` may need to be
updated to match new String API. If the build dies in Hesper, drop the
patch and rebuild — Phase 1 will skip Hesper rather than fail the
whole image.)

### Drop a module

To ship without Sparkle (saves ~5 MB compressed):

1. Comment out the `lake build SparkleDemo` line in `Dockerfile.wasm`.
2. The pack script will skip Sparkle automatically (no `Sparkle.olean`
   in the install prefix).
3. Frontend will not auto-import it.

### Add your own library

Two options:

1. **Easy**: drop your `.olean` files under
   `$(pixi info -e wasm-host --json | jq -r .environments_info[0].prefix)/share/jupyter/olean/MyLib`
   inside the image, name your top-level olean
   `MyLib.olean`, and re-run the pack step. The runtime will pick it
   up via the same manifest.
2. **Cleanest**: write a `mylib-wasm/build-wasm.sh` analogous to
   `hesper-wasm/build-wasm.sh`, then add an "include MyLib in pack"
   line near the existing Hesper symlink in `Dockerfile.wasm`
   (`scripts/pack-olean-modules.sh` knows about it via
   the `MODULES` list — edit that to add `MyLib`).

## Step 4 — Run the E2E tests against your local build

The `xeus-lean-e2e` image (Playwright + Chromium) runs the same
e2e suite the CI uses:

```bash
# Build the e2e tooling image once
docker build -f Dockerfile.e2e -t xeus-lean-e2e .

# Run tests against a freshly built _output
docker create --name xeus-lean-tmp xeus-lean-wasm
docker cp xeus-lean-tmp:/app/dist ./_output
docker rm xeus-lean-tmp

docker run --rm \
  -v "$(pwd)/_output:/work/_output:ro" \
  -v "$(pwd)/tests:/work/tests:rw" \
  -v "$(pwd)/notebooks:/work/notebooks:ro" \
  -e CI=1 \
  xeus-lean-e2e \
  bash -lc 'cd /work/tests/e2e && ./node_modules/.bin/playwright test'
```

Output goes to `tests/e2e/playwright-report/` and
`tests/e2e/test-results/`.

## Common gotchas

- **`fzstd not loaded — cannot decompress tarballs`** — the WASM
  binary was built against an older `src/post.js` that fetched fzstd
  from a CDN. Rebuild with the current sources; the CDN fetch is gone.
- **Tarballs download but kernel never reaches "Idle"** — your
  `xlean.js` is older than the `Module.preRun` post.js fix
  (commit `a54fcf2`). Rebuild xlean.
- **`olean.server` files missing for Init.Prelude** — known issue
  with cmake's `file(COPY)` on certain filesystems; the test_wasm_node
  staging recipe in `CMakeLists.txt` now uses `cp -r` to dodge it.

## Next

- [Browser tutorial](browser-jupyterlite.md) — same site you just
  built, hosted at github.io.
- [Native via Docker](docker-native.md) — when WASM limitations get
  in the way.
