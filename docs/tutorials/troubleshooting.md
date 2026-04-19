# Troubleshooting

Symptom-keyed cheat sheet. If yours isn't here, open an issue with
the relevant section's diagnostics command's output.

## Browser / WASM

### Page loads but kernel says "Unknown" forever

Open DevTools console and look for `[olean]` lines.

| Symptom | Likely cause | Fix |
|---|---|---|
| `[olean] no manifest-v2.json` | the deployment is missing the manifest at `/xeus/wasm-host/olean/` | confirm the static site contains `_output/xeus/wasm-host/olean/manifest-v2.json` |
| `[olean] manifest-v2 found ... wrote 0 / N files` | post.js ran before WASM was instantiated (`fizztd ok` then writes silently dropped) | rebuild xlean with the current `src/post.js` (uses `Module.preRun`) — see commit `a54fcf2` |
| `[olean] fzstd not loaded` | xlean.js is built without the inlined `src/fzstd.umd.js` | rebuild xlean with the current CMakeLists (two `--post-js` flags) |
| `RuntimeError: memory access out of bounds` after a few `#eval` cells | known WASM Lean memory64 bug in `importModulesCore` (5th fresh import) | already worked around by env-reuse — make sure `WasmRepl.lean` and `Frontend.lean` are current |

### Tarballs 404

```
GET /xeus/wasm-host/olean/Std-olean.tar.zst HTTP/1.1 404
```

The pack step didn't run, or its output didn't make it into the
deployment. Check:

```bash
ls _output/xeus/wasm-host/olean/
# Expect:  Hesper-olean.tar.zst  Lean-olean.tar.zst
#          Sparkle-olean.tar.zst Std-olean.tar.zst  manifest-v2.json
```

If the directory has raw `.olean` files instead, JupyterLite copied
them and the pack step didn't replace them. Re-run:

```bash
rm -rf _output/xeus/wasm-host/olean
mkdir _output/xeus/wasm-host/olean
bash scripts/pack-olean-modules.sh \
    "$PIXI_PREFIX/share/jupyter/olean" \
    _output/xeus/wasm-host/olean ''
```

### `import Sparkle` works in Cell 1 but a later `import Foo` is silently ignored

By design. The WASM kernel reuses the environment from Cell 1 to
work around a Lean memory64 bug, so subsequent cells skip the import
phase entirely. Auto-imports happen on the first cell only.

To add a library, rebuild the WASM site with that library bundled
(see [docker-wasm.md](docker-wasm.md) "Add your own library").

### My JS / WGSL string is wrong but Lean doesn't tell me

`#eval` output is stdout; if your code throws inside `unsafeIO` or a
similar block, the message goes to **stderr** which appears in the
browser console, not the cell output. Check DevTools.

## Native build

### `wasm-ld: error: symbol exported via --export not found: sparkle_cache_get`

You ran the WASM build (in Docker) without first running
`lake build SparkleDemo`. The Sparkle IR `.cpp` files weren't
generated, so `sparkle_barrier.cpp`'s diagnostic wrapper that defines
those symbols never got compiled. Either:

- Run `cd examples/sparkle && lake build SparkleDemo` before the
  cmake step, or
- Use `Dockerfile.wasm` which already does this.

### `error: Hesper/WGSL/Exp.lean: patch does not apply`

You ran `hesper-wasm/build-wasm.sh` twice without resetting the
submodule between runs. The script's `EXIT` trap should restore the
working tree, but a previous interrupted run can leave it dirty.

```bash
cd hesper
git checkout -- .
rm -f lakefile.lean.xeus-bak lakefile.toml.xeus-bak lean-toolchain.xeus-bak
cd ..
```

### `undefined reference to __isoc23_strtoull` (Linux native)

System glibc → C23 redirects, Lean's bundled glibc → no C23
symbols. Build the shim:

```bash
leanc -c src/glibc_isoc23_compat.c -o build-cmake/glibc_isoc23_compat.o
```

(It's already in the build via `target_link_libraries`; if you
deleted `build-cmake/` and only re-ran `lake build`, this object is
gone. Either re-run `cmake --build build-cmake` or run the `leanc`
line directly.)

### `lean: command not found`

elan installed `lean`/`lake` to `$HOME/.elan/bin`, which isn't on
PATH by default. Add to your shell profile:

```bash
export PATH="$HOME/.elan/bin:$PATH"
```

### "Lean 4" missing from JupyterLab launcher

```bash
jupyter kernelspec list
```

If `xlean` isn't listed, run `lake run installKernel`. If it IS
listed but not in the launcher, restart JupyterLab (the launcher
caches kernel specs at startup).

## CI

### Pages limit warning

A single Pages deployment is capped at ~1 GB. Current `_output/` is
~850 MB. If you add another large library, switch the manifest's
`baseUrl` to a GitHub Releases URL — the runtime will fetch tarballs
from there instead of the static site, removing the 1 GB cap.
See `docs/tutorials/docker-wasm.md` "Customizing what gets bundled."

### CI takes >15 minutes

Most of the time is the `emmake make xlean` step (~12 min) and the
`wasm-opt` post-link pass (~5 min). Both are CPU-bound and can be
parallelized but not skipped. The CI cache helps incremental rebuilds
but a clean run will always be slow. The Docker image (~18 GB)
caches the heavy bits between runs once you have it locally.

## Filing a bug

Include:

- Which path you used (browser / docker-native / docker-wasm /
  from-source) and exact step you ran.
- For browser: DevTools console, especially `[olean]` and any red
  error lines.
- For native: `cmake --build build-cmake 2>&1 | tail -50` and
  `lake build xlean 2>&1 | tail -50`.
- For WASM build: the last 80 lines of the failing make / lake step.
- `git rev-parse HEAD` so we know what commit you tried.
