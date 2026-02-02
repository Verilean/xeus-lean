# Contributing to xeus-lean

Thank you for your interest in contributing to xeus-lean!

## Development Setup

### Prerequisites

- **CMake** >= 3.10
- **C++17** compatible compiler (GCC, Clang, or MSVC)
- **Lean 4** toolchain (via elan)
- **Lake** (Lean build tool)
- System dependencies: nlohmann_json, zeromq, cppzmq

### Building from Source

```bash
# Clone the repository
git clone <repository-url>
cd xeus-lean

# Build C++ FFI library
mkdir -p build-cmake && cd build-cmake
cmake ..
cmake --build .
cd ..

# Build Lean kernel
lake build xlean
```

### Running Tests

```bash
# Quick test
python3 test_clean_output.py

# Test with Jupyter
jupyter lab
# Create notebook, select Lean 4 kernel
```

## Project Structure

```
xeus-lean/
├── src/
│   ├── XeusKernel.lean         # Main event loop (Lean-owned)
│   ├── xeus_ffi.cpp            # C++ FFI layer
│   └── REPL/                   # Lean REPL implementation
│       ├── Main.lean           # Command execution
│       ├── JSON.lean           # Serialization
│       └── Frontend.lean       # Lean integration
├── include/
│   └── xeus_ffi.h              # FFI declarations
├── build-cmake/
│   ├── CMakeLists.txt          # C++ build config
│   └── libxeus_ffi.a           # Static library (generated)
├── lakefile.lean               # Lake build config
└── *.md                        # Documentation
```

## Architecture Overview

### Control Flow

**Key Insight**: Lean owns the main event loop, not C++!

```
Jupyter → ZMQ → xeus (C++ thread) → message queue
                                          ↓
Lean main loop → FFI poll() → get message → execute → FFI send_result()
```

### Components

1. **Lean Main Loop** (`src/XeusKernel.lean`)
   - `main()`: Entry point
   - `kernelLoop()`: Event loop (polls via FFI)
   - `parseMessage()`: Parses JSON from C++
   - `formatOutput()`: Clean text for info, JSON for errors

2. **C++ FFI Layer** (`src/xeus_ffi.cpp`)
   - `xeus_kernel_init()`: Initialize xeus in background thread
   - `xeus_kernel_poll()`: Non-blocking message poll
   - `xeus_kernel_send_result()`: Send result to Jupyter
   - `lean_interpreter`: Implements xeus interface (queues messages)

3. **REPL Module** (`src/REPL/`)
   - `runCommand()`: Execute Lean code
   - Environment tracking across executions
   - Message formatting (errors, info, warnings)

## Making Changes

### Code Style

**Lean:**
- Use 2-space indentation
- Document public APIs with `/--` comments
- Follow Lean naming conventions (camelCase for functions)

**C++:**
- Use 4-space indentation
- Include copyright headers
- Use DEBUG_LOG macro for debugging output
- Keep error messages visible (std::cerr for errors)

### Adding Features

#### 1. New REPL Commands

Edit `src/REPL/Main.lean`:

```lean
-- Add new command handling
def runCommand (cmd : Command) : StateT State IO (Except Error Response) := do
  ...
  -- Your new command logic here
```

#### 2. Enhanced Output Formatting

Edit `src/XeusKernel.lean`:

```lean
-- Modify formatOutput to handle new message types
let formattedJson :=
  if hasSpecialOutput then
    formatSpecial response
  else
    defaultFormat response
```

#### 3. New FFI Functions

**C++ side** (`src/xeus_ffi.cpp`):

```cpp
extern "C" lean_object* xeus_kernel_my_function(
    lean_object* handle,
    lean_object* param,
    lean_object* /* world */) {
    try {
        auto* state = to_kernel_state(handle);
        // Your implementation
        return lean_io_result_mk_ok(result);
    } catch (const std::exception& e) {
        std::cerr << "[C++ FFI] Error: " << e.what() << std::endl;
        return lean_io_result_mk_error(...);
    }
}
```

**Lean side** (`src/XeusKernel.lean`):

```lean
@[extern "xeus_kernel_my_function"]
opaque myFunction (handle : @& KernelHandle) (param : @& String) : IO Result
```

#### 4. Tab Completion (TODO)

Needs implementation:

**C++ side**: Add `complete_request_impl` handler
**Lean side**: Query environment for identifiers
**FFI**: Add `xeus_kernel_complete()` function

### Testing

When adding features, please:

1. **Write unit tests**: Add to test scripts
2. **Test with Jupyter**: Verify in notebook
3. **Test error handling**: Ensure errors display correctly
4. **Check memory**: Run with XLEAN_DEBUG=1
5. **Test environment persistence**: Ensure definitions persist

### Common Tasks

#### Improving Error Messages

Edit formatting in `src/XeusKernel.lean`:

```lean
-- Format errors with better structure
let hasErrors := response.messages.any (fun m =>
  match m.severity with
  | .info => false
  | _ => true)
```

#### Adding Debug Logging

**Lean:**
```lean
debugLog "[Component] Message here"
```

**C++:**
```cpp
DEBUG_LOG("[Component] Message here");
```

Both respect `XLEAN_DEBUG` environment variable.

#### Supporting New Display Types

Edit C++ FFI to add MIME types:

```cpp
void send_result(int exec_count, const std::string& result) {
    json pub_data;
    pub_data["text/plain"] = result;
    pub_data["text/html"] = to_html(result);  // New!
    pub_data["text/latex"] = to_latex(result);  // New!
    publish_execution_result(exec_count, pub_data, json::object());
}
```

## Debugging

### Enable Debug Mode

```bash
XLEAN_DEBUG=1 jupyter lab
```

Shows:
- FFI initialization
- Message polling
- Execution flow
- Environment transitions
- Memory operations

### Test FFI Directly

```bash
# Build with debug symbols
cd build-cmake
cmake .. -DCMAKE_BUILD_TYPE=Debug
cmake --build .
cd ..

# Rebuild Lean
lake build xlean

# Run tests
python3 test_clean_output.py
```

### Check REPL Behavior

Use `src/REPL/Main.lean` directly:

```lean
import REPL

open REPL

def testREPL : IO Unit := do
  let cmd : Command := { cmd := "def x := 42", env := none, ... }
  let initialState : State := { cmdStates := #[], proofStates := #[] }
  let result ← runCommand cmd |>.run initialState
  IO.println (toJson result)

#eval testREPL
```

### Debug Memory Issues

**Check external object registration:**
```bash
XLEAN_DEBUG=1 ./lake/build/bin/xlean test_connection.json 2>&1 | \
  grep "register_external_class"
```

**Check for pointer corruption:**
```bash
XLEAN_DEBUG=1 ./lake/build/bin/xlean test_connection.json 2>&1 | \
  grep "state="
```

## Submitting Changes

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/my-feature`)
3. **Make** your changes
4. **Add** tests
5. **Update** documentation
6. **Commit** with clear message:
   ```
   Add tab completion support

   - Implement complete_request_impl in C++
   - Add environment query in Lean
   - Add xeus_kernel_complete FFI function
   - Update documentation
   ```
7. **Push** to your fork
8. **Submit** pull request

## Pull Request Guidelines

- Include motivation for the change
- Reference related issues
- Add tests if applicable
- Update relevant documentation
- Ensure CI passes (if available)

## Areas Needing Help

### High Priority
- [ ] **Tab Completion**: Query Lean environment for identifiers
- [ ] **Inspection**: Implement Shift+Tab (type info)
- [ ] **Installation Script**: Auto-create kernel.json
- [ ] **Better Errors**: Highlight error positions in notebook

### Medium Priority
- [ ] **LaTeX Rendering**: Format proof goals
- [ ] **Syntax Highlighting**: Better code display
- [ ] **File Loading**: Support loading .lean files
- [ ] **Mathlib Testing**: Verify with Mathlib imports

### Low Priority
- [ ] **Windows Support**: Port to Windows
- [ ] **Shared Library**: Investigate why it fails
- [ ] **Performance**: Optimize FFI call overhead
- [ ] **WebAssembly**: JupyterLite support

## Architecture Notes for Contributors

### Why Lean Owns the Loop

**Traditional kernels:**
```cpp
int main() {
  while (running) {
    msg = receive();
    result = execute_python(msg);
    send(result);
  }
}
```

**xeus-lean:**
```lean
def main : IO Unit := do
  while running do
    msg ← poll_via_ffi()
    result ← execute_lean(msg)
    send_via_ffi(result)
```

**Benefits:**
- Clean Lean runtime integration
- Direct environment access
- No subprocess overhead
- Simpler memory management
- Single process debugging

### Memory Management

**Lean GC manages everything:**
- External objects for C++ state
- Automatic cleanup via finalizers
- No manual memory management in Lean code

**C++ responsibilities:**
- Allocate kernel state
- Register with Lean GC
- Implement finalizer
- Don't touch Lean objects' internals

### Static Linking Requirement

**Why static?**
- Shared libraries crashed in `lean_register_external_class()`
- Root cause unclear (possibly initialization order)
- Static linking works perfectly

**Trade-off:**
- Larger binary size (~50MB)
- But: simpler deployment (single file)

## Getting Help

- **Questions**: Open an issue
- **Bugs**: Provide XLEAN_DEBUG=1 output
- **Features**: Discuss in issue first
- **Documentation**: xeus docs at https://xeus.readthedocs.io/

## Code of Conduct

Please be respectful and constructive:
- Welcome newcomers
- Provide helpful feedback
- Focus on technical merits
- Assume good intentions

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.

## Acknowledgments

Contributors will be listed in the project README. Thank you for your contributions!

## Development Resources

- **Lean Manual**: https://lean-lang.org/lean4/doc/
- **xeus Documentation**: https://xeus.readthedocs.io/
- **Jupyter Protocol**: https://jupyter-client.readthedocs.io/
- **Lake Manual**: https://github.com/leanprover/lake

## Contact

- **Issues**: GitHub issue tracker
- **Discussions**: GitHub discussions (if enabled)
- **Email**: See maintainers in git log
