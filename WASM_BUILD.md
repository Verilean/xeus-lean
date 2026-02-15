# WASM Build: Architecture & Bottlenecks

Lean 4 Jupyter kernel compiled entirely to WebAssembly via emscripten Memory64.
Runs in the browser through JupyterLite with no server-side Lean installation.

## Architecture

```
                          Host (macOS/Linux)
  ┌──────────────────────────────────────────────────────────┐
  │  lake build WasmRepl                                     │
  │    └─> .lake/build/ir/{REPL,WasmRepl}.c  (Lean → C)     │
  │                                                          │
  │  emcmake cmake + emmake make                             │
  │    ├─ libleanrt_wasm.a    (lean4 runtime, patched)       │
  │    ├─ lean_stage0_{init,std,lean}.a  (Init/Std/Lean .c)  │
  │    ├─ lean_stage0_repl.a  (REPL + WasmRepl .c from lake) │
  │    ├─ xeus-lean-static.a  (xinterpreter_wasm.cpp)        │
  │    ├─ xeus-static / xeus-lite  (FetchContent, wasm64)    │
  │    └─ wasm_symbol_table.cpp  (generated at build time)   │
  │         │                                                │
  │         ▼                                                │
  │    xlean.js + xlean.wasm  (emscripten output)            │
  │      └─ Init .olean/.ir files embedded via --embed-file  │
  │                                                          │
  │  jupyter lite build                                      │
  │    └─> _output/  (static JupyterLite site)               │
  └──────────────────────────────────────────────────────────┘

                          Browser
  ┌──────────────────────────────────────────────────────────┐
  │  JupyterLite  ──Web Worker──>  xlean.js                  │
  │                                  │                       │
  │                                  ▼                       │
  │                        createXeusModule()                │
  │                          ├─ Lean runtime init            │
  │                          ├─ import Init (.olean VFS)     │
  │                          └─ REPL execute loop            │
  └──────────────────────────────────────────────────────────┘
```

## 5 Key Bottlenecks & Solutions

### 1. Task System — `g_task_manager` is null in WASM

**Problem**: Lean 4's elaborator and `#eval` use promises and tasks (`lean_promise_new`,
`lean_task_map_core`, `lean_task_bind_core`). These all assert `g_task_manager != nullptr`.
In single-threaded WASM there are no worker threads, so `g_task_manager` stays null after
`lean_init_task_manager_using(0)`.

**Symptom**: `#eval 1+1` → PANIC at `realizeValue`; `#eval "hello"` → crash.

**Solution** (7 patches in `cmake/LeanRtWasm.cmake`, Patches 1–6 on `object.cpp`):

| Patch | Function | Fix |
|-------|----------|-----|
| 1 | `lean_promise_new` | Remove `g_task_manager` assertion |
| 2 | `lean_promise_resolve` | Synchronous resolve when `g_task_manager` is null |
| 3 | `lean_task_get` | Lazy evaluation: if task has a closure, execute it on demand |
| 3b | `lean_task_map_core` | Create deferred task instead of synchronous call when source has no value |
| 3c | `lean_task_bind_core` | Same deferred pattern as 3b |
| 3d | `task_map_fn` | Null-check `m_value` with `lean_task_get` fallback |
| 3e | `task_bind_fn1` | Same null-check as 3d |
| 4 | `lean_io_check_canceled_core` | Null-safe `g_task_manager->shutting_down()` |
| 5 | `lean_io_cancel_core` | Null-safe `g_task_manager->cancel()` |
| 6 | `deactivate_promise` | Synchronous resolve on GC when no task manager |

The key insight is that tasks must be **deferred** (not executed immediately) when the
source promise hasn't been resolved yet, then **lazily evaluated** when their value is
first requested via `lean_task_get`.

### 2. Message Loss — `elabCommandTopLevel` resets per command

**Problem**: Lean 4.28's `elabCommandTopLevel` resets `Command.State.messages` at the
start of each command. The standard `Frontend.processCommands` loop returns only the
final command state, which contains messages from the last command only (typically the
EOF marker, which has none).

**Symptom**: REPL returns 0 messages for `#check Nat`, `#eval 1+1`, etc.

**Solution** (`src/REPL/Frontend.lean`): `processCommandsAccum` accumulates `MessageLog`
and `InfoTree` across all commands, collecting them after each `processCommand` call
instead of relying on the final state.

### 3. Symbol Resolution — `dlsym` doesn't work in WASM

**Problem**: Lean's IR interpreter (`ir_interpreter.cpp`) calls `dlsym(RTLD_DEFAULT, sym)`
to find `@[extern]` function implementations at runtime. In WASM, `dlsym` doesn't work
without `-sMAIN_MODULE=1`, which in turn prevents `ALLOW_MEMORY_GROWTH` from working
(causing `std::bad_alloc` when loading Init modules).

**Symptom**: Any `@[extern]` call or module initialization silently fails.

**Solution**: Build-time static symbol table generation:
1. `cmake/GenerateSymbolTable.cmake` — orchestrates the generation
2. `cmake/gen_wasm_symtab.sh` — extracts symbols from `.a` files via `llvm-nm`,
   filters to `initialize_*`, `lean_*`, `l_initFn*`, `*___boxed`
3. Generated `wasm_symbol_table.cpp` — sorted array + binary search
4. `ir_interpreter.cpp` patch — `#ifdef LEAN_EMSCRIPTEN` routes to `wasm_lookup_symbol()`

### 4. ABI Mismatches — IO world token erasure, hash truncation, frexpf bug

**Problem**: Three categories of signature mismatches between Lean-generated C code and
hand-written C++ runtime:

| Category | Example | Root Cause |
|----------|---------|------------|
| IO world token | `lean_uv_os_get_group()` vs `lean_uv_os_get_group(uint64_t)` | Lean compiler erases the `IO.RealWorld` token |
| Hash truncation | `unsigned operator()(name const&)` in `std::unordered_map` | Hash functors return `unsigned` (32-bit) but `sizeof(size_t)` is 8 on wasm64 |
| frexpf | `frexp(float, int*)` overload | emscripten libc++ generates wasm32 `frexpf` import in wasm64 mode |

**Symptom**: `unreachable` traps at runtime; hash table corruption (infinite loops).

**Solution**:
- `cmake/fix_extern_signatures.py` — automatically detects and fixes IO world token
  mismatches by comparing `.c` declarations with `.cpp` definitions
- Manual patches in `LeanRtWasm.cmake` — fix specific `uint8*`→`uint8_t`,
  `lean_obj_res`→`uint8_t`, and `unsigned`→`std::size_t` in hash functors
- Patch 7 — replace `frexp(float,int*)` with `frexpf(float,int*)` directly

### 5. Memory64 — .olean format is pointer-size dependent

**Problem**: Lean's `.olean` files (compiled module data) use pointer-sized values
internally. Host `.olean` files are compiled for 64-bit (8-byte pointers). WASM defaults
to 32-bit pointers (4 bytes), causing `.olean` loading to fail with corrupted data.

**Symptom**: `import Init` fails or produces garbage.

**Solution** (`CMakeLists.txt`): Compile everything with `-sMEMORY64`:
- Set via `CMAKE_C_FLAGS`/`CMAKE_CXX_FLAGS` (not `add_compile_options`) so flags
  propagate to all `FetchContent` subdirectories (xeus, xeus-lite, xtl, nlohmann_json)
- All `.olean`/`.ir` files embedded at `/lib/lean/` in the WASM VFS via `--embed-file`
- Requires `node --experimental-wasm-memory64` for testing

## Deployment

```bash
# Full pipeline: build everything + serve JupyterLite on :8888
make deploy

# Or step-by-step:
make lake        # Generate .c files from Lean source
make configure   # emcmake cmake
make build       # emmake make (xlean + test_wasm_node)
make test        # Run test_wasm_node.js in Node.js
make install     # Install to .pixi/envs/wasm-host
make lite        # Build JupyterLite static site
make serve       # Serve _output/ on :8888
```

Prerequisites: `nix-shell -p emscripten cmake gnumake python3 nodejs_24`

## File Reference

| File | Purpose |
|------|---------|
| `CMakeLists.txt` | Top-level build: dual EMSCRIPTEN/native paths, FetchContent deps, .olean embedding |
| `cmake/LeanRtWasm.cmake` | Fetch lean4 source, apply all runtime patches, build `libleanrt_wasm.a` |
| `cmake/LeanStage0Wasm.cmake` | Build stage0 `.c` files (Init/Std/Lean/REPL) as WASM static libs |
| `cmake/GenerateSymbolTable.cmake` | Orchestrate `gen_wasm_symtab.sh` to generate dlsym replacement |
| `cmake/gen_wasm_symtab.sh` | Extract symbols with `llvm-nm`, generate sorted C++ lookup table |
| `cmake/fix_extern_signatures.py` | Auto-fix IO world token signature mismatches between `.c` and `.cpp` |
| `cmake/stubs/` | Libuv stubs and additional WASM stubs for missing lean4 extern functions |
| `src/REPL/Frontend.lean` | `processCommandsAccum` — message accumulation fix |
| `src/WasmRepl.lean` | Lean REPL exports (`@[export]`) called from C++ via FFI |
| `src/xinterpreter_wasm.cpp` | xeus interpreter: init Lean runtime, call REPL, format output |
| `src/main_emscripten_kernel.cpp` | WASM entry point for xeus-lite kernel |
| `src/pre.js` / `src/post.js` | Emscripten pre/post JS for module setup |
| `test_wasm_node.cpp` | Standalone Node.js test: hash tables + Lean init + 5 REPL commands |
| `lakefile.lean` | Lake build config: `WasmRepl` lib target for `.lean` → `.c` compilation |
| `Makefile` | Build automation: `make deploy` for full pipeline |
