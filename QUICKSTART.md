# Quick Start Guide

Get xeus-lean running in 5 minutes!

## Prerequisites

### System Dependencies

**macOS (using Homebrew):**
```bash
brew install cmake nlohmann-json zeromq cppzmq
```

**Ubuntu/Debian:**
```bash
sudo apt-get install cmake nlohmann-json3-dev libzmq3-dev libcppzmq-dev
```

### Lean 4

Install Lean via elan (if not already installed):
```bash
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh
source ~/.elan/env
```

### Jupyter

```bash
pip3 install jupyter jupyterlab
```

## Build xeus-lean

### Step 1: Clone Repository

```bash
git clone <repository-url>
cd xeus-lean
```

### Step 2: Build C++ FFI Library

```bash
# Create build directory
mkdir -p build-cmake
cd build-cmake

# Configure (downloads xeus, xeus-zmq automatically)
cmake ..

# Build libxeus_ffi.a
cmake --build .

cd ..
```

This creates:
- `build-cmake/libxeus_ffi.a` (static library)
- `build-cmake/_deps/xeus-build/libxeus.a`
- `build-cmake/_deps/xeus-zmq-build/libxeus-zmq.a`

### Step 3: Build Lean Kernel

```bash
# Build xlean executable (links with FFI library)
lake build xlean
```

This creates `.lake/build/bin/xlean` - the final Jupyter kernel executable.

### Step 4: Install Kernel Spec

```bash
# Create Jupyter kernel directory
mkdir -p ~/.local/share/jupyter/kernels/xlean

# Create kernel.json
cat > ~/.local/share/jupyter/kernels/xlean/kernel.json <<EOF
{
  "display_name": "Lean 4",
  "language": "lean",
  "argv": [
    "$(pwd)/.lake/build/bin/xlean",
    "{connection_file}"
  ]
}
EOF
```

### Step 5: Verify Installation

```bash
jupyter kernelspec list
# Should show:
#   xlean    /Users/<you>/.local/share/jupyter/kernels/xlean
```

## Test the Kernel

### Option 1: Quick Test with Python

```bash
python3 test_clean_output.py
```

Should output:
```
✓ Clean output!
✓ Full JSON for errors (as expected)
```

### Option 2: Jupyter Console

```bash
jupyter console --kernel=xlean
```

Try:
```lean
def hello := "Hello from Lean!"
#eval hello
-- Output: "Hello from Lean!"
```

### Option 3: Jupyter Lab

```bash
jupyter lab
```

Create a new notebook and select "Lean 4" as the kernel.

## Example Session

```lean
-- Cell 1: Define a function
def fibonacci : Nat → Nat
  | 0 => 0
  | 1 => 1
  | n + 2 => fibonacci (n + 1) + fibonacci n

-- Cell 2: Evaluate
#eval fibonacci 10
-- Output: 55

-- Cell 3: IO actions
def main : IO Unit := IO.println "Hello from Lean!"
#eval main
-- Output: Hello from Lean!

-- Cell 4: Definitions persist!
#eval fibonacci 15
-- Output: 610 (fibonacci from Cell 1 is still available)
```

## Debug Mode

Enable verbose logging if something goes wrong:

```bash
XLEAN_DEBUG=1 jupyter lab
```

This shows:
- FFI initialization
- Message polling
- Execution flow
- Environment transitions

## Troubleshooting

### Kernel doesn't appear in Jupyter

Check kernel spec:
```bash
jupyter kernelspec list
cat ~/.local/share/jupyter/kernels/xlean/kernel.json
```

Ensure the `argv` path is correct and absolute.

### Kernel starts but doesn't execute

Test directly:
```bash
./.lake/build/bin/xlean test_connection.json
```

Should wait without errors. Kill with Ctrl+C.

### Build errors

**CMake can't find nlohmann_json:**
```bash
# macOS
brew install nlohmann-json

# Ubuntu
sudo apt-get install nlohmann-json3-dev
```

**Lake can't find libxeus_ffi.a:**
```bash
# Ensure C++ build completed
ls build-cmake/libxeus_ffi.a

# Rebuild if missing
cd build-cmake && cmake --build . && cd ..
```

**Link errors about xeus or xeus-zmq:**
```bash
# Check libraries exist
ls build-cmake/_deps/xeus-build/libxeus.a
ls build-cmake/_deps/xeus-zmq-build/libxeus-zmq.a

# Clean and rebuild
cd build-cmake
rm -rf _deps
cmake ..
cmake --build .
cd ..
```

### Import errors in notebook

Ensure you're in a directory with a valid `lakefile.lean` if using imports:
```bash
cd /path/to/your/lean/project
jupyter lab
```

### IO functions don't work

Ensure `supportInterpreter := true` in `lakefile.lean`:
```lean
lean_exe xlean where
  root := `XeusKernel
  supportInterpreter := true  -- Must be true!
```

## Build Script (Alternative)

Use the provided build script:
```bash
./build.sh
```

This runs both CMake and Lake builds.

## Updating

```bash
# Update C++ dependencies
cd build-cmake
cmake .. --fresh
cmake --build .
cd ..

# Rebuild Lean kernel
lake clean
lake build xlean
```

## Uninstall

```bash
# Remove kernel spec
jupyter kernelspec uninstall xlean

# Remove build artifacts
rm -rf build-cmake .lake
```

## Performance Tips

1. **First execution is slow**: Lean initializes search paths and loads stdlib
2. **Subsequent executions are fast**: Environment is cached
3. **Large imports are slow**: Mathlib can take several seconds
4. **Enable debug mode sparingly**: Verbose logging affects performance

## Next Steps

- Read `README.md` for detailed features
- See `IMPLEMENTATION_NOTES.md` for architecture details
- Check `CONTRIBUTING.md` for development guide
- Try `examples/` directory for sample notebooks

## Common Workflows

### Development Workflow

```bash
# Edit Lean code
vim src/XeusKernel.lean

# Rebuild
lake build xlean

# Test
python3 test_clean_output.py

# Or test in Jupyter
jupyter lab
```

### C++ FFI Changes

```bash
# Edit C++ code
vim src/xeus_ffi.cpp

# Rebuild C++
cd build-cmake && cmake --build . && cd ..

# Rebuild Lean (re-links)
lake build xlean

# Test
python3 test_clean_output.py
```

### REPL Module Changes

```bash
# Edit REPL code
vim src/REPL/Main.lean

# Rebuild (Lake handles dependencies)
lake build xlean

# Test
python3 test_clean_output.py
```

## Getting Help

- **Build issues**: Check `build-cmake/CMakeOutput.log`
- **Runtime issues**: Run with `XLEAN_DEBUG=1`
- **Lake issues**: Run `lake build xlean --verbose`
- **Jupyter issues**: Check `jupyter --paths` for config locations

## System Requirements

- **Disk space**: ~500MB for dependencies
- **RAM**: ~2GB (Lean + xeus + Jupyter)
- **Platforms**: macOS, Linux (Windows untested)
- **Lean version**: 4.x (check `lean-toolchain` file)
