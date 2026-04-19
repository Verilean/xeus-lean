# Native build from source (30 minutes)

For when you want to hack on the kernel itself — change FFI surfaces,
add commands, debug the Lean main loop, etc. No Docker.

## Prerequisites

- Linux or macOS (Windows works under WSL2)
- ~5 GB free disk
- A C++17 compiler (clang strongly preferred — see notes below)
- `cmake ≥ 3.16`, `git`, `curl`
- One of:
  - **Linux**: `apt install nlohmann-json3-dev libzmq3-dev cppzmq-dev uuid-dev libssl-dev libc++-dev libc++abi-dev clang`
  - **macOS**: `brew install nlohmann-json zeromq cppzmq ossp-uuid openssl`

## Step 1 — Install Lean

```bash
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
    -sSf | sh -s -- -y --default-toolchain leanprover/lean4:v4.28.0-rc1

# Pick up `lean` and `lake` in your shell
export PATH="$HOME/.elan/bin:$PATH"
lean --version  # Lean 4.28.0-rc1, ...
```

(Pin matters: the kernel uses Lean's stage0 stdlib internals; matching
the toolchain in `lean-toolchain` avoids ABI mismatches.)

## Step 2 — Clone

```bash
git clone --recursive https://github.com/Verilean/xeus-lean.git
cd xeus-lean
```

`--recursive` pulls the Hesper submodule. If you forgot, run
`git submodule update --init --recursive` after the clone.

## Step 3 — Build the C++ FFI library

```bash
cmake -S . -B build-cmake \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_CXX_FLAGS="-stdlib=libc++"

cmake --build build-cmake -j
```

**Why `clang -stdlib=libc++`?** Lean's `leanc` is built against a
specific libc++. Mixing libstdc++ from system gcc with Lean's libc++
gives ABI-mismatch link errors. Using clang + libc++ everywhere
sidesteps the whole class of bugs. If you're on a system where libc++
isn't packaged separately (older Ubuntu), install `libc++-dev libc++abi-dev`.

(Apple's clang already uses libc++; on macOS you can drop the
`-stdlib=libc++` flag.)

## Step 4 — Linux only: glibc C23 shim

Modern clang against modern glibc redirects some C functions to
`__isoc23_*` symbols (e.g. `__isoc23_strtoull`). Lean's bundled
glibc doesn't have those. Build the small forwarding shim with
`leanc` so the symbols match:

```bash
leanc -c src/glibc_isoc23_compat.c -o build-cmake/glibc_isoc23_compat.o
```

(macOS skips this step.)

## Step 5 — Build the kernel

```bash
lake build xlean
```

This compiles everything Lean-side: `XeusKernel.lean`, `REPL/*`,
`Display.lean`, `WasmRepl.lean`, plus stage0 stdlib bits Lake decides
it needs. The result is `.lake/build/bin/xlean` (~50 MB binary).

Smoke-test:

```bash
.lake/build/bin/xlean --version  # prints version banner, then exits
```

## Step 6 — Install the kernelspec

```bash
lake run installKernel
```

That writes `~/.local/share/jupyter/kernels/xlean/kernel.json`
pointing at the binary you just built.

## Step 7 — Launch Jupyter

```bash
pip install --user jupyterlab
jupyter lab
```

In the launcher pick **Lean 4**. Open or create a notebook, type
`#eval 1 + 1`, Shift+Enter.

## Optional: Sparkle

```bash
cd examples/sparkle
lake update
lake build SparkleDemo

# Make Sparkle.olean discoverable (next time you launch jupyter)
export LEAN_PATH="$PWD/.lake/packages/sparkle/.lake/build/lib/lean:$LEAN_PATH"

cd ../..
jupyter lab
```

In a notebook:

```lean
import Sparkle
open Sparkle.Core.Domain Sparkle.Core.Signal

def counter4 : Signal defaultDomain (BitVec 4) :=
  Signal.circuit do
    let count ← Signal.reg 0#4
    count <~ count + 1#4
    return count

#eval IO.println s!"counter: {counter4.val 0}"
```

The `Signal.loop` interpreter path runs natively here (it hangs in
WASM — that's a separate bug).

## Optional: Hesper WGSL DSL

```bash
bash hesper-wasm/build-wasm.sh hesper /tmp/hesper-staging \
    Hesper.WGSL.DSL Hesper.WGSL.Helpers
export LEAN_PATH="/tmp/hesper-staging:$LEAN_PATH"
jupyter lab
```

Then in a notebook:

```lean
import Hesper.WGSL.DSL
open Hesper.WGSL
def e : Exp (.scalar .f32) := Exp.var "x"
#eval IO.println e.toWGSL
```

The full Hesper library (with native WebGPU via Dawn, GLFW, SIMD via
Highway) needs Hesper's own native build — see `hesper/README.md`.
The WASM wrapper used here just builds the pure-Lean WGSL subset.

## Iteration loop

After editing Lean files in `src/`:

```bash
lake build xlean
# Restart the kernel from JupyterLab (Kernel → Restart)
```

After editing C++ files in `src/`:

```bash
cmake --build build-cmake -j
lake build xlean   # relinks against the rebuilt static lib
```

## Troubleshooting

- **`undefined reference to __isoc23_strtoull`** — you skipped Step 4.
- **`undefined reference to std::__1::...`** vs **`std::__cxx11::...`**
  in linker output — you have a libc++/libstdc++ mismatch. Re-run
  Step 3 with the `-stdlib=libc++` flag, and make sure cmake clears
  its cache (`rm -rf build-cmake` then re-configure).
- **`lean: command not found`** — Step 1's `export PATH=` didn't
  persist. Add it to `~/.bashrc`/`~/.zshrc`.
- **Kernel doesn't appear in JupyterLab launcher** — `lake run
  installKernel` puts the spec under `~/.local/share/jupyter/kernels/xlean/`.
  Verify with `jupyter kernelspec list`. If it's there but doesn't
  appear, restart JupyterLab (the launcher caches the list).

## Next

- [Try Sparkle simulation](docker-native.md) — works on native, hangs
  on WASM today.
- [Reproduce the JupyterLite site](docker-wasm.md) — same kernel,
  different deploy target.
