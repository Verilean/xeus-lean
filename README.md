# xeus-lean

A Jupyter kernel for [Lean 4](https://lean-lang.org/) based on the
[xeus](https://github.com/jupyter-xeus/xeus) framework. Runs both as a
**native desktop kernel** and as a **WASM kernel in the browser** via
JupyterLite — so a reader can try Lean without installing anything.

> ⚠️ **What this project is, and isn't.**
>
> This is a playground.  The goal is to let curious people read a
> chapter, click into a cell, and *feel* what writing a small Lean
> definition or formal statement is like — all from inside a browser
> tab.
>
> It is **not** a substitute for the proper Lean development environment.
> If you want to *do real proof work* — interactive infoview, gutter
> diagnostics, term-mode hovers, tactic suggestions, project-wide
> elan/lake — install
> [VS Code with the Lean 4 extension](https://leanprover-community.github.io/install/vscode.html)
> and follow that path.  The browser build trades depth for
> zero-install reach.
>
> So: don't expect VS Code parity.  Don't file bugs about missing
> `lean --print-prefix` ergonomics.  Treat this as the "free trial"
> that gets a reader hooked enough to install the real thing.

## What you can actually do in your browser

- Read tutorials with pictures and runnable cells side-by-side.
- Press <kbd>Shift</kbd>+<kbd>Enter</kbd> on a cell, see Lean evaluate it.
- Modify the cell and re-run it.  State carries from cell to cell.
- Optional: load Mathlib chunks on demand with `%load mathlib` and try
  Mathlib theorems live.

What *not* to expect in the browser kernel:

- Interactive goal-state infoview (use VS Code).
- Project-wide refactoring or lake-aware diagnostics (use VS Code).
- A "Save" that round-trips to your repo (the JupyterLite filesystem
  is a single-tab IndexedDB; export your notebook to download it).
- Performance parity with native (the WASM kernel uses ~2 GB per tab
  and takes seconds for a cold boot).

## Where to start

### Just reading / trying Lean

Click into the live site:

→ **https://verilean.github.io/xeus-lean/lab/index.html**

There's a starter notebook, a small Mathlib demo (run `%load mathlib`
in the first cell, then `import Mathlib.Tactic`), and the
function-language tutorial pre-loaded.

If you want to learn Lean as a *programming language* before touching
proofs, jump to the
[function-language tutorial](docs/tutorial/md/README.md) and skim
Ch00–Ch16.

If you want to see what Lean + Mathlib feels like *for math*, open
[`docs/math-visual/`](docs/math-visual/) and start with the complex
analysis Ch01.  Those chapters are deliberately Needham-style: a
picture, some numerical play, then the formal Lean statement.

### Tutorials (where the docs are)

| Track | Path | What it is |
|---|---|---|
| **Lean as a language** | [`docs/tutorial/md/`](docs/tutorial/md/README.md) | Ch00–Ch16: setup, values, pattern matching, types, lists, arrays, strings, hashmaps, error handling, IO, file I/O, processes, sockets, concurrency, JSON, macros, type-level programming with Haskell comparisons. |
| **Lean as math** | [`docs/math-visual/`](docs/math-visual/README.md) | Visual-Complex-Analysis-style chapters: conformal maps, Möbius, Riemann sphere, contour integrals, manifolds, category theory, optimal transport, etc. Each chapter: a picture → numerical exploration → a formal Mathlib statement → "try it yourself" exercises. |
| **Operating xeus-lean** | [`docs/tutorials/`](docs/tutorials/) | Browser / Docker / source-build instructions and a troubleshooting guide. |
| **Authoring tutorials** | [`docs/Convert.md`](docs/Convert.md) | The `xlean-convert` CLI that turns one Markdown source into `.ipynb`, runnable `.lean`, static HTML site, or output-baked Markdown. |

### Quick-start install matrix

| Target | Time | Reach |
|---|---:|---|
| **Browser** (no install) | 1 min | [live site](https://verilean.github.io/xeus-lean/lab/index.html) or run the static build locally — fully serverless, no Python, no Node. |
| **Pre-built Docker (native kernel)** | 10 sec | `docker run --rm -it -p 8888:8888 ghcr.io/verilean/xeus-lean:latest` gives you JupyterLab with the xlean kernel and Display lib. |
| **Docker build (native)** | 10 min | [`docs/tutorials/docker-native.md`](docs/tutorials/docker-native.md) — build the base image yourself. |
| **Docker build (WASM, with Mathlib)** | 30–60 min | [`docs/tutorials/docker-wasm.md`](docs/tutorials/docker-wasm.md) — reproduce the JupyterLite site, optionally bundling Mathlib. |
| **From source (native)** | 30 min | [`docs/tutorials/native-from-source.md`](docs/tutorials/native-from-source.md) — for hacking on the kernel itself. |

## Self-hosting the browser site

If you want to put the same JupyterLite experience behind your own
URL — for a class, a workshop, or to bundle a different Mathlib
snapshot — there are three reasonable paths.

### Option A — Reuse the upstream GitHub Pages output

The simplest path: serve the prebuilt site under your own domain
without re-running the WASM build.

1. Clone the live deployment branch:

    ```bash
    git clone --branch gh-pages https://github.com/verilean/xeus-lean.git xeus-lean-site
    ```

2. Serve `xeus-lean-site/` with any static HTTP server. The whole site
   is a couple of GB; serve it from a CDN (Cloudflare Pages, Netlify,
   Vercel) or any HTTP host that can serve files up to ~1.3 GB
   (the largest Mathlib chunk).

    ```bash
    cd xeus-lean-site
    python3 -m http.server 8000   # or your favourite static server
    ```

3. Open `http://localhost:8000/lab/index.html`. That's it — the
   kernel is entirely client-side, your server only delivers files.

### Option B — Build locally, serve the `_output/` directory

If you want to bundle your own additions (custom notebooks, your
project's Lean lib, a Mathlib snapshot pinned to your toolchain),
build the JupyterLite site locally and serve it the same way.

```bash
git clone https://github.com/verilean/xeus-lean
cd xeus-lean

# WASM build with Mathlib (slow: 30-60 min on a fast laptop)
make docker-e2e-image-with-mathlib

# The built site lives in the image under /work/_output
docker run --rm -it -p 8765:8765 --name xeus-serve xeus-lean-e2e \
  bash -c 'cd /work/_output && python3 -m http.server 8765'
```

Visit `http://localhost:8765/lab/index.html`.

To bundle your own notebooks, drop them into `notebooks/` before
building; the WASM Dockerfile copies that directory into the
`jupyter lite build --contents` step.

### Option C — Drop the WASM site behind any static host

The `_output/` from option B is a plain static site. Any of:

- **GitHub Pages**: push the `_output/` content to a `gh-pages`
  branch. Caveat: Mathlib chunks exceed GitHub's 100 MB single-file
  warning; for full Mathlib hosting you'll want a CDN-backed origin.
- **Cloudflare Pages / Netlify / Vercel**: upload `_output/` as the
  publish directory. Configure the `Cross-Origin-Embedder-Policy`
  / `Cross-Origin-Opener-Policy` headers if you need SharedArrayBuffer
  (xeus-lean's WASM build *doesn't* require it today, but JupyterLite
  some extensions do).
- **S3 / GCS / any object store**: serve as a website bucket.

No runtime backend is needed. The entire Lean kernel — runtime,
Mathlib oleans, JupyterLite shell — is downloaded once and runs in
the user's tab.

### Where Mathlib lives in the bundle

Mathlib oleans are split into per-namespace chunks
(`Mathlib.Algebra`, `Mathlib.Topology`, …) under
`_output/xeus/wasm-host/olean/` so a tab can fetch only what its
notebook actually uses (`%load mathlib` triggers the fetches on
demand). Total bundle size with all chunks: ~1.7 GB compressed. Total
size of the default-no-Mathlib site: ~280 MB compressed.

## Other things this project does

- **Rich display in cells** — `Display.html`, `Display.latex`,
  `Display.svg`, `Display.markdown`, `Display.bv`, `Display.verilog`,
  `Display.waveform`, `Display.blockDiagram`, `Display.mermaid`.
- **Notebook helpers** — `#help_x` lists registered commands;
  `#findDecl` / `#listNs` / `#sig` search the env;
  `#bash`, `#mermaid`, `#savefig`.
- **Comm protocol on the WASM side** — used for interactive widgets
  like the waveform viewer.
- **Docs pipeline** — [`docs/Convert.md`](docs/Convert.md): one
  Markdown source → `.ipynb`, runnable `.lean:percent`, a static HTML
  site, or evaluated-output-baked Markdown.

## Architecture sketch

```
Native:
  Jupyter Client ──ZMQ──▶ Lean Main (XeusKernel.lean)
                               │  FFI
                          C++ xeus (xeus_ffi.cpp)

WASM (in-browser, no server):
  Browser tab ──Web Worker──▶ xlean.js + xlean.wasm (Memory64)
                                   │
                              Lean runtime, single-threaded
                                   │
                              MEMFS populated from .tar.zst
                              chunks fetched on demand
                              + IndexedDB cache for warm boots
```

For the kernel internals — the five WASM bottlenecks we hit, the
env-reuse workaround, the per-module zstd tarball pipeline — see
[`WASM_BUILD.md`](WASM_BUILD.md). For Mathlib loading, see the
comments inside `src/post.js`.

## Extending the kernel with your own Lean lib

Downstream projects (Sparkle, Hesper, …) extend
`ghcr.io/verilean/xeus-lean` by lake-building their own Lean lib and
re-linking xlean against it. The mechanism is `XEUS_LEAN_EXTRA_LIBS`,
a generic env-var-driven extension point in `lakefile.lean`. Sketch
Dockerfile:

```dockerfile
FROM ghcr.io/verilean/xeus-lean:latest

COPY my-lib/ /app/my-lib/
RUN cd /app/my-lib && lake update && lake build mylib

# Bundle compiled olean objects into a static archive.
RUN cd /app/my-lib/.lake/packages/mylib/.lake/build/ir && \
    find . -name '*.c.o.export' ! -name 'Main.c.o.export' -print0 \
      | xargs -0 ar rcs /app/build-cmake/libmy_olean.a

# Relink xlean. --whole-archive is required because no symbol in xlean
# directly references project libs (the Lean interpreter looks them up
# at runtime), so a normal link would drop them as dead code.
RUN rm -f /app/.lake/build/bin/xlean && \
    XEUS_LEAN_EXTRA_LIBS="-Wl,--whole-archive \
      /app/build-cmake/libmy_olean.a \
      /app/my-lib/.lake/.../libmy_ffi.a \
      -Wl,--no-whole-archive" \
    lake build xlean
```

`Dockerfile.native-sparkle` is the worked example.

## CI / CD

GitHub Actions builds both targets on every push:

- **Native**: Linux x86_64, uploads `xlean` binary
- **WASM**: emscripten Memory64, runs `test_wasm_node`, deploys
  JupyterLite to GitHub Pages

## License

Apache License 2.0.

## Acknowledgments

- **[xeus](https://github.com/jupyter-xeus/xeus)** — Jupyter kernel
  protocol framework, by QuantStack.
- **[Lean 4 REPL](https://github.com/leanprover-community/repl)** —
  the basis for `src/REPL/`, by the Lean community.
- **[JupyterLite](https://github.com/jupyterlite/jupyterlite)** — the
  in-browser Jupyter runtime that hosts the WASM kernel.
- **[Mathlib](https://github.com/leanprover-community/mathlib4)** —
  the formal-math library; the per-namespace chunks under
  `xeus/wasm-host/olean/Mathlib.*-olean.tar.zst` come from Mathlib's
  build for our pinned Lean toolchain.
