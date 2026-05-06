# xeus-lean

A Jupyter kernel for [Lean 4](https://lean-lang.org/) based on the [xeus](https://github.com/jupyter-xeus/xeus) framework.
Runs both as a **native desktop kernel** and as a **WASM kernel in the browser** via JupyterLite.

## Features

- **Interactive Lean 4** in Jupyter notebooks — `#eval`, `#check`, `def`, `theorem`, etc.
- **Environment persistence** — definitions carry across cells
- **Two build targets**:
  - **Native**: Lean-owned main loop, C++ xeus via FFI, runs in Jupyter Lab/Notebook
  - **WASM**: Compiled to WebAssembly via emscripten Memory64, runs in JupyterLite (browser, no server needed)

## Quick Start

Pick whichever path matches your setup. Each tutorial is self-contained
and copy-pasteable.

| Path | Time | What you get |
|------|-----:|-----|
| [Browser](docs/tutorials/browser-jupyterlite.md) | 1 min | JupyterLite at github.io, no install |
| **Pre-built base image** | 10 sec | `docker run --rm -it -p 8888:8888 ghcr.io/verilean/xeus-lean:latest` — JupyterLab + xlean kernel + Display lib (no Sparkle) |
| [Docker — native kernel](docs/tutorials/docker-native.md) | 10 min | Build the base image locally |
| [Docker — WASM build](docs/tutorials/docker-wasm.md) | 30 min | Reproduce the JupyterLite static site, customize bundled libs |
| [From source — native](docs/tutorials/native-from-source.md) | 30 min | Hack on the kernel itself |

### Building on top of the base image

Downstream projects (Sparkle, Hesper, …) extend `ghcr.io/verilean/xeus-lean` by lake-building their own Lean lib and re-linking xlean against it. The mechanism is `XEUS_LEAN_EXTRA_LIBS`, a generic env-var-driven extension point in `lakefile.lean`. Sketch:

```dockerfile
FROM ghcr.io/verilean/xeus-lean:latest

# Pull and build the project's Lean lib + any C FFI it ships.
COPY my-lib/ /app/my-lib/
RUN cd /app/my-lib && lake update && lake build mylib

# Bundle compiled olean objects into a static archive (skip Main.c.o.export
# so it doesn't clash with xlean's lean_main).
RUN cd /app/my-lib/.lake/packages/mylib/.lake/build/ir && \
    find . -name '*.c.o.export' ! -name 'Main.c.o.export' -print0 \
      | xargs -0 ar rcs /app/build-cmake/libmy_olean.a

# Relink xlean. --whole-archive is required because no symbol in
# xlean directly references project libs (the Lean interpreter looks
# them up at runtime), so a normal link would drop them as dead code.
RUN rm -f /app/.lake/build/bin/xlean && \
    XEUS_LEAN_EXTRA_LIBS="-Wl,--whole-archive \
      /app/build-cmake/libmy_olean.a \
      /app/my-lib/.lake/.../libmy_ffi.a \
      -Wl,--no-whole-archive" \
    lake build xlean
```

This keeps xeus-lean free of any project-specific build dependency. See `Dockerfile.native-sparkle` for the worked example.

Stuck? See the [troubleshooting guide](docs/tutorials/troubleshooting.md).

For internals (the 5 WASM bottlenecks, the env-reuse workaround, the
per-module zstd tarball pipeline), see [WASM_BUILD.md](WASM_BUILD.md).

## Example Session

```lean
-- Cell 1: Define a function
def factorial : Nat → Nat
  | 0 => 1
  | n + 1 => (n + 1) * factorial n

-- Cell 2: Evaluate
#eval factorial 10  -- 3628800

-- Cell 3: Type check
#check @List.map  -- {α β : Type} → (α → β) → List α → List β

-- Cell 4: IO actions
#eval IO.println "Hello from Lean!"  -- Hello from Lean!
```

## Architecture

### Native

```
Jupyter Client ──ZMQ──▶ Lean Main (XeusKernel.lean)
                             │ FFI
                        C++ xeus (xeus_ffi.cpp)
```

Lean owns the main loop, polls for Jupyter messages, and calls the C++ xeus library via FFI.

### WASM

```
Browser ──Web Worker──▶ xlean.js + xlean.wasm
                             │
                        Lean runtime (patched for single-threaded WASM)
                        + Init .olean files (embedded in VFS)
```

The entire Lean 4 runtime and Init module are compiled to WASM with emscripten Memory64
(`-sMEMORY64` for 64-bit pointers matching host `.olean` format).

## Project Structure

```
xeus-lean/
├── src/
│   ├── XeusKernel.lean              # Native: Lean main loop
│   ├── xeus_ffi.cpp                 # Native: C++ FFI layer
│   ├── xinterpreter_wasm.cpp        # WASM: xeus-lite interpreter
│   ├── main_emscripten_kernel.cpp   # WASM: entry point
│   ├── WasmRepl.lean                # WASM: REPL exports (@[export])
│   ├── REPL/                        # REPL implementation
│   │   └── Frontend.lean            # Message accumulation fix
│   ├── pre.js / post.js             # Emscripten JS hooks
├── cmake/
│   ├── LeanRtWasm.cmake             # Build lean4 runtime for WASM
│   ├── LeanStage0Wasm.cmake         # Build stage0 stdlib for WASM
│   ├── GenerateSymbolTable.cmake    # dlsym replacement for WASM
│   ├── fix_extern_signatures.py     # Auto-fix ABI mismatches
│   └── stubs/                       # Libuv stubs for WASM
├── CMakeLists.txt                   # Dual native/WASM build
├── Makefile                         # WASM build automation
├── lakefile.lean                    # Lake build config
├── pixi.toml                        # Pixi environments (emscripten, jupyterlite)
├── WASM_BUILD.md                    # WASM architecture & bottleneck docs
└── test_wasm_node.cpp               # WASM integration tests
```

## CI/CD

GitHub Actions builds both targets on every push:
- **Native build**: Linux x86_64, uploads `xlean` binary
- **WASM build**: emscripten Memory64, runs `test_wasm_node`, deploys JupyterLite to GitHub Pages

## License

Apache License 2.0

## Acknowledgments

- **[xeus](https://github.com/jupyter-xeus/xeus)** by QuantStack — Jupyter kernel protocol framework
- **[Lean 4 REPL](https://github.com/leanprover-community/repl)** by the Lean community — `src/REPL/` is based on this project
- **[xeus-lite](https://github.com/jupyter-xeus/xeus-lite)** — xeus for JupyterLite/WASM
