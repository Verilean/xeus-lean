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

### Try in the Browser (WASM)

Visit the [GitHub Pages deployment](https://verilean.github.io/xeus-lean/) — no installation required.

### Native Build

```bash
# Install Lean 4 via elan
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh -s -- -y

# Build
cmake -S . -B build-cmake
cmake --build build-cmake
lake build xlean

# Install kernel spec and launch
lake run installKernel
jupyter lab  # Select "Lean 4" kernel
```

### WASM Build

Requires: [nix](https://nixos.org/download/) and [pixi](https://pixi.sh/)

```bash
# Full pipeline: build + test + JupyterLite site + serve on :8888
make deploy

# Or step-by-step:
make lake        # Generate .c files from Lean source
make configure   # emcmake cmake
make build       # emmake make (xlean + test_wasm_node)
make test        # Run WASM tests in Node.js
make deploy      # Build JupyterLite site + serve
```

See [WASM_BUILD.md](WASM_BUILD.md) for architecture details and the 5 key bottlenecks solved.

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
