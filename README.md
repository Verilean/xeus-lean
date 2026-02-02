# xeus-lean

A Jupyter kernel for Lean 4 based on the [xeus](https://github.com/jupyter-xeus/xeus) framework.

## Overview

`xeus-lean` is a Jupyter kernel for Lean 4 that enables interactive theorem proving and programming in Jupyter notebooks. Unlike traditional kernel designs, **Lean owns the main event loop** and calls the C++ xeus library via FFI (Foreign Function Interface). This architecture provides clean integration with Lean's runtime while leveraging the robust xeus implementation of the Jupyter protocol.

## Features

- **Interactive Lean 4**: Execute Lean code in Jupyter notebooks
- **Environment Persistence**: State is maintained across cells with environment tracking
- **Clean Output**: Info messages display as plain text, errors show detailed JSON
- **IO Support**: Full support for `IO` actions including `IO.println`
- **Error Messages**: Formatted error output with position information
- **Debug Mode**: Optional verbose logging via `XLEAN_DEBUG` environment variable
- **Native Performance**: Direct FFI calls with no subprocess overhead

## Architecture

```
┌─────────────────┐
│ Jupyter Client  │
│  (Notebook/Lab) │
└────────┬────────┘
         │ Jupyter Protocol (ZMQ)
┌────────▼────────┐
│   Lean Main     │  ← Lean owns the event loop
│  (XeusKernel)   │
└────────┬────────┘
         │ FFI calls
┌────────▼────────┐
│  C++ xeus lib   │  ← Static library (libxeus_ffi.a)
│  (xeus_ffi.cpp) │
└────────┬────────┘
         │ ZMQ
┌────────▼────────┐
│  xeus framework │
│   (protocol)    │
└─────────────────┘
```

**Key Design**:
- **Lean main loop** (`src/XeusKernel.lean`) polls for messages and executes code
- **C++ FFI layer** (`src/xeus_ffi.cpp`) exposes xeus functionality to Lean
- **REPL integration** (`src/REPL/`) provides command evaluation (from [leanprover-community/repl](https://github.com/leanprover-community/repl))
- **Static linking** bundles everything into single `xlean` executable

## Dependencies

- **CMake** (>= 3.10)
- **C++17** compiler
- **xeus** (>= 5.0.0)
- **xeus-zmq** (>= 1.0.2)
- **nlohmann_json**
- **Lean 4** toolchain (via elan)
- **Lake** (Lean build tool)

## Building from Source

```bash
# 1. Clone the repository
git clone <repository-url>
cd xeus-lean

# 2. Build C++ dependencies (xeus, xeus-zmq)
./build.sh

# 3. Build xlean kernel
lake build xlean

# 4. Install kernel spec (creates Jupyter kernel specification)
# TODO: Add installation script

# 5. Verify installation
jupyter kernelspec list  # Should show xlean
```

## Usage

### Jupyter Lab

```bash
jupyter lab
# Create a new notebook and select "Lean 4" kernel
```

### Jupyter Notebook

```bash
jupyter notebook
# Select "Lean 4" from the kernel menu
```

### Example Session

```lean
# Cell 1: Define a function
def factorial : Nat → Nat
  | 0 => 1
  | n + 1 => (n + 1) * factorial n

# Cell 2: Evaluate
#eval factorial 5  -- Output: 120

# Cell 3: IO actions
def main : IO Unit := IO.println "Hello from Lean!"
#eval main  -- Output: Hello from Lean!

# Cell 4: Definitions persist
#eval factorial 10  -- Can use factorial from Cell 1
```

## Environment Persistence

The kernel tracks Lean environment IDs across cells:
- Each successful cell execution returns a new environment ID
- Subsequent cells use the previous environment ID
- Definitions, theorems, and imports persist throughout the session
- Errors don't update the environment (retry with same state)

Example:
```lean
# Cell 1
def x := 42  -- env: 0 → 1

# Cell 2
def y := x + 1  -- env: 1 → 2 (x is available)

# Cell 3
#eval y  -- env: 2, outputs: 43
```

## Output Formatting

The kernel provides clean output for regular execution:
- **Info messages**: Display as plain text (e.g., `#eval` results)
- **Errors**: Show full JSON with position, severity, and hints
- **Empty results**: No output for pure definitions

Example:
```lean
#eval IO.println "Hello"
-- Output: Hello

#eval 1 + "string"
-- Output: {
--   "env": 2,
--   "messages": [{
--     "severity": "error",
--     "data": "type mismatch...",
--     ...
--   }]
-- }
```

## Debug Mode

Enable verbose logging with the `XLEAN_DEBUG` environment variable:

```bash
# Normal mode (quiet)
jupyter lab

# Debug mode (verbose logging)
XLEAN_DEBUG=1 jupyter lab
```

Debug output includes:
- FFI initialization steps
- Message polling and parsing
- Execution flow
- Environment state transitions
- Mutex and memory operations

## Configuration

### Build Configuration

Edit `lakefile.lean` to adjust:
- Link paths for xeus libraries
- Interpreter support flag
- Compiler options

### Runtime Configuration

The kernel uses Jupyter's standard connection file mechanism. Advanced users can:
- Specify custom connection files
- Adjust ZMQ ports
- Configure kernel timeouts

## Known Limitations

1. **REPL Elaborator**: Limited support for infix operators in some contexts
   - Use `Nat.add 1 1` instead of `1 + 1` if issues arise
   - Import Lean provides more elaborate context
2. **Static Linking Required**: Shared library builds had issues with external class registration
3. **Platform Support**: Currently tested on macOS and Linux

## Troubleshooting

### Kernel doesn't start
```bash
# Check xlean executable
ls .lake/build/bin/xlean

# Run directly to see errors
./.lake/build/bin/xlean test_connection.json
```

### Static linking errors
```bash
# Rebuild C++ FFI library
cd build-cmake
rm libxeus_ffi.a
cmake --build . --target xeus_ffi

# Rebuild xlean
cd ..
lake clean
lake build xlean
```

### Import errors
```bash
# Ensure Lean search path is initialized
# Check lean-toolchain matches your Lean version
cat lean-toolchain
```

## Project Structure

```
xeus-lean/
├── src/
│   ├── XeusKernel.lean         # Main event loop (Lean owns this)
│   ├── xeus_ffi.cpp            # C++ FFI exports to Lean
│   └── REPL/                   # Lean REPL implementation
│                               # (from github.com/leanprover-community/repl)
├── include/
│   └── xeus_ffi.h              # FFI function declarations
├── build-cmake/
│   └── libxeus_ffi.a           # Static library (C++ → Lean)
├── lakefile.lean               # Lake build configuration
├── CMakeLists.txt              # C++ build configuration
└── README.md                   # This file
```

## Comparison with Other Jupyter Kernels

| Aspect | xeus-python | xeus-lean |
|--------|-------------|-----------|
| Language runtime | Python interpreter | Lean 4 runtime |
| Main loop ownership | C++ xeus | Lean |
| Language integration | Embedded Python | FFI to C++ |
| State management | Python context | Environment IDs |
| Build complexity | Medium | High (FFI + static link) |

## License

Apache License 2.0

## Contributing

Contributions are welcome! Key areas:
- Better error message formatting
- Enhanced completion support
- Rich display for proof goals
- Documentation improvements

See `CONTRIBUTING.md` for development guidelines.

## Acknowledgments

This project builds upon the excellent work of:

- **[xeus](https://github.com/jupyter-xeus/xeus) framework** by QuantStack - provides the robust Jupyter kernel protocol implementation
- **[Lean 4 REPL](https://github.com/leanprover-community/repl)** by the Lean community - the `src/REPL/` directory contains code from this project, which provides the command evaluation and elaboration infrastructure
- **[xeus-zmq](https://github.com/jupyter-xeus/xeus-zmq)** - ZMQ-based messaging implementation for xeus
- Various xeus-based kernel implementations that inspired this architecture
