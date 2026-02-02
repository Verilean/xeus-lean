# xeus-lean Implementation Notes

## Architecture: Lean-Owned Event Loop with FFI to C++ xeus

xeus-lean uses an **inverted architecture** where Lean owns the main event loop and calls C++ xeus via FFI.

### Architecture Diagram

```
┌────────────────────────────────────────────────┐
│         Jupyter Client (Browser)               │
└─────────────────┬──────────────────────────────┘
                  │ Jupyter Protocol (ZMQ)
┌─────────────────▼──────────────────────────────┐
│              Lean Runtime                       │
│  ┌──────────────────────────────────────────┐  │
│  │  XeusKernel.lean (main event loop)       │  │
│  │  - kernelLoop(): polls & executes        │  │
│  │  - Environment tracking                  │  │
│  │  - Output formatting                     │  │
│  └──────────────────┬───────────────────────┘  │
│                     │ FFI calls (@[extern])     │
│  ┌──────────────────▼───────────────────────┐  │
│  │  C++ FFI Layer (xeus_ffi.cpp)            │  │
│  │  - xeus_kernel_init()                    │  │
│  │  - xeus_kernel_poll()                    │  │
│  │  - xeus_kernel_send_result()             │  │
│  │  - lean_interpreter (xeus interface)     │  │
│  └──────────────────┬───────────────────────┘  │
│                     │ C++ calls                 │
│  ┌──────────────────▼───────────────────────┐  │
│  │  xeus Library                             │  │
│  │  - ZMQ communication                      │  │
│  │  - Jupyter protocol                       │  │
│  │  - Message formatting                     │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
     All linked statically into xlean executable
```

### Key Design Principle

**Control Inversion**: Instead of C++ embedding Lean, Lean embeds C++.

**Why?**
- Lean needs full control of its runtime and environment
- Simpler memory management (Lean GC manages everything)
- Direct access to Lean's elaboration context
- No subprocess/pipe overhead
- Single binary deployment

## Implementation Details

### 1. Lean Side: XeusKernel.lean

**Main Entry Point:**
```lean
def main (args : List String) : IO Unit := do
  let connectionFile := args.get? 0 |>.getD "connection.json"

  -- Initialize Lean search path
  Lean.initSearchPath (← Lean.findSysroot)

  -- Initialize FFI and xeus kernel
  ffiInitialize
  let some handle ← kernelInit connectionFile | throw ...

  -- Initialize REPL state
  let replState ← IO.mkRef initialState

  -- Run main event loop (THIS is where control stays)
  kernelLoop handle replState none
```

**Event Loop:**
```lean
partial def kernelLoop (handle : KernelHandle)
                       (replState : IO.Ref State)
                       (currentEnv : Option Nat) : IO Unit := do
  -- Poll for Jupyter messages (FFI call, non-blocking)
  let msgJson ← kernelPoll handle 100  -- 100ms timeout

  if msgJson.isEmpty then
    let shouldStop ← kernelShouldStop handle
    if shouldStop then return ()
    else kernelLoop handle replState currentEnv
  else
    -- Parse and handle message
    match ← parseMessage msgJson with
    | .executeRequest code execCount =>
      -- Execute Lean code using REPL
      let cmd := { cmd := code, env := currentEnv, ... }
      let result ← runCommand cmd |>.run replState

      -- Format and send result
      match result with
      | (.inl response, newState) =>
        kernelSendResult handle execCount (formatOutput response)
        kernelLoop handle replState (some response.env)  -- Update env!

      | (.inr error, newState) =>
        kernelSendError handle execCount (toJson error)
        kernelLoop handle replState currentEnv  -- Keep same env
```

**Key Features:**
- **Environment Tracking**: `currentEnv : Option Nat` threads through recursion
- **Clean Output**: Format based on message severity
- **Debug Logging**: Controlled by `XLEAN_DEBUG` env var
- **Non-blocking**: Poll with timeout, doesn't block Lean runtime

### 2. C++ Side: xeus_ffi.cpp

**FFI Function Exports:**

```cpp
// Initialize FFI (register external classes)
lean_object* xeus_ffi_initialize(lean_object* /* world */);

// Initialize xeus kernel, return handle
lean_object* xeus_kernel_init(lean_object* connection_file,
                               lean_object* /* world */);

// Poll for messages (non-blocking, timeout in ms)
lean_object* xeus_kernel_poll(lean_object* handle,
                               uint32_t timeout_ms,
                               lean_object* /* world */);

// Send execution result back to Jupyter
lean_object* xeus_kernel_send_result(lean_object* handle,
                                      uint32_t exec_count,
                                      lean_object* result,
                                      lean_object* /* world */);

// Send error message
lean_object* xeus_kernel_send_error(lean_object* handle,
                                     uint32_t exec_count,
                                     lean_object* error,
                                     lean_object* /* world */);

// Check if shutdown requested
lean_object* xeus_kernel_should_stop(lean_object* handle,
                                      lean_object* /* world */);
```

**Memory Management:**

Uses Lean's external object system:

```cpp
// State managed by Lean GC
struct KernelState {
    std::unique_ptr<xeus::xkernel> kernel;
    std::unique_ptr<xeus::xcontext> context;
    lean_interpreter* interpreter;  // Raw pointer (kernel owns)
    std::thread kernel_thread;
};

// Finalizer called by Lean GC
extern "C" void finalize_kernel_state(void* ptr) {
    auto* state = static_cast<KernelState*>(ptr);
    if (state->kernel_thread.joinable()) {
        state->kernel_thread.join();
    }
    delete state;
}

// Register with Lean
lean_external_class* g_kernel_state_class =
    lean_register_external_class(finalize_kernel_state, nullptr);

// Allocate external object
lean_object* handle = lean_alloc_external(g_kernel_state_class, state);
```

**lean_interpreter Class:**

Implements xeus interpreter interface:

```cpp
class lean_interpreter : public xeus::xinterpreter {
    std::queue<std::string> m_message_queue;
    std::mutex m_message_mutex;
    send_reply_callback m_current_callback;

public:
    // Called by xeus when message arrives
    void execute_request_impl(send_reply_callback cb,
                              int execution_count,
                              const std::string& code, ...) override {
        // Queue message for Lean to poll
        std::lock_guard lock(m_message_mutex);
        json msg = {
            {"type", "execute_request"},
            {"code", code},
            {"execution_count", execution_count}
        };
        m_message_queue.push(msg.dump());
        m_current_callback = cb;  // Save for later reply
    }

    // Lean polls this
    std::string poll_message() {
        std::lock_guard lock(m_message_mutex);
        if (m_message_queue.empty()) return "";
        std::string msg = m_message_queue.front();
        m_message_queue.pop();
        return msg;
    }

    // Lean sends result here
    void send_result(int exec_count, const std::string& result) {
        // Parse as JSON or use as text
        json pub_data;
        try {
            auto parsed = json::parse(result);
            pub_data["text/plain"] = parsed.dump(2);
        } catch (json::parse_error&) {
            pub_data["text/plain"] = result;  // Plain text
        }

        publish_execution_result(exec_count, pub_data, json::object());

        if (m_current_callback) {
            m_current_callback(xeus::create_successful_reply());
            m_current_callback = nullptr;
        }
    }
};
```

**Threading Model:**

```cpp
// xeus kernel runs in background thread
state->kernel_thread = std::thread([kernel_ptr]() {
    kernel_ptr->start();  // Blocks in xeus event loop
});

// Lean main thread polls via FFI
while (true) {
    string msg = state->interpreter->poll_message();
    // Process msg in Lean
    state->interpreter->send_result(...);
}
```

### 3. Build System

**CMake (C++ FFI Library):**

```cmake
# Build xeus_ffi static library
add_library(xeus_ffi STATIC src/xeus_ffi.cpp)

# Fetch and build xeus dependencies
FetchContent_Declare(xeus GIT_REPOSITORY ...)
FetchContent_Declare(xeus-zmq GIT_REPOSITORY ...)

target_link_libraries(xeus_ffi
    PUBLIC xeus xeus-zmq nlohmann_json::nlohmann_json)
```

**Lake (Lean Executable):**

```lean
lean_exe xlean where
  root := `XeusKernel
  supportInterpreter := true  -- Enable IO native implementations

  moreLinkArgs := #[
    "./build-cmake/libxeus_ffi.a",  -- Static FFI library
    "-L./build-cmake/_deps/xeus-build",
    "-L./build-cmake/_deps/xeus-zmq-build",
    "-lxeus",
    "-lxeus-zmq",
    "-lstdc++"
  ]
```

**Build Order:**

1. CMake configures and downloads xeus, xeus-zmq
2. CMake builds `libxeus_ffi.a`
3. Lake builds Lean sources (`.lean` → `.c` → `.o`)
4. Lake links everything into `xlean` executable

### 4. REPL Integration

Uses the Lean REPL module from leanprover-community:

```lean
-- Execute Lean command
let cmd : REPL.Command := {
  cmd := code,           -- Source code
  env := currentEnv,     -- Previous environment (or none)
  infotree := none,
  allTactics := none,
  rootGoals := none
}

let result ← runCommand cmd |>.run replState

match result with
| (.inl response, newState) =>  -- Success
  -- response.env : Nat (new environment ID)
  -- response.messages : List Message
  ...
| (.inr error, newState) =>      -- Error
  -- error.messages : List Message with severity
  ...
```

**Environment IDs:**
- Start: `env = none` (empty environment)
- After `def x := 42`: `env = 1`
- After `def y := x + 1`: `env = 2`
- Environment contains all definitions, imports, theorems

## Critical Implementation Decisions

### 1. Static vs Shared Linking

**Problem:** Shared library build crashes in `lean_register_external_class()`

**Root Cause:** Unclear, possibly related to how shared libraries handle static initialization of external classes.

**Solution:** Use `STATIC` library:
```cmake
add_library(xeus_ffi STATIC src/xeus_ffi.cpp)
```

**Result:** External class registration works perfectly.

### 2. USize vs External Objects

**Problem:** Using `USize` to pass C++ pointers caused corruption:
```lean
-- Boxed USize: 0x10bcc7090
-- Unboxed in next call: 0x10bcc73c0  (DIFFERENT!)
```

**Root Cause:** Lean's reference counting treated USize as a Lean value.

**Solution:** Use Lean external objects:
```cpp
lean_object* handle = lean_alloc_external(ext_class, state);
```
```lean
opaque KernelHandle : Type  -- Opaque, Lean won't touch internals
```

**Result:** Pointers remain valid, no corruption.

### 3. Environment Persistence

**Problem:** Each cell started with empty environment, definitions didn't persist.

**Root Cause:** Always passing `env := none` to REPL commands.

**Solution:** Thread environment ID through loop:
```lean
partial def kernelLoop ... (currentEnv : Option Nat) : IO Unit := do
  ...
  let cmd := { ..., env := currentEnv }  -- Use current!
  ...
  kernelLoop handle replState (some response.env)  -- Update!
```

**Result:** Definitions persist across cells.

### 4. IO Support

**Problem:** `IO.println` failed with "IO.getStdout not found"

**Root Cause:** `supportInterpreter := false` disables native IO implementations.

**Solution:** Enable in lakefile:
```lean
lean_exe xlean where
  supportInterpreter := true
```

**Result:** All IO functions work.

### 5. Verbose Output

**Problem:** Every output showed full JSON structure.

**Solution:** Format based on severity:
```lean
let hasErrors := messages.any (fun m => m.severity != .info)
if hasErrors then
  Lean.toJson response |>.compress  -- Full JSON
else
  String.intercalate "\n" (messages.map (·.data))  -- Clean text
```

**Result:** Clean output for simple evaluations.

## Debug Mode

### Environment Variable

Set `XLEAN_DEBUG=1` to enable verbose logging:

```bash
XLEAN_DEBUG=1 jupyter lab
```

### Implementation

**Lean side:**
```lean
def isDebugEnabled : IO Bool := do
  let env ← IO.getEnv "XLEAN_DEBUG"
  return env.isSome && (env.get! == "1" || env.get! == "true")

def debugLog (msg : String) : IO Unit := do
  if ← isDebugEnabled then IO.eprintln msg
```

**C++ side:**
```cpp
inline bool is_debug_enabled() {
    static bool debug = []() {
        const char* env = std::getenv("XLEAN_DEBUG");
        return env != nullptr && std::string(env) == "1";
    }();
    return debug;
}

#define DEBUG_LOG(msg) \
    do { if (is_debug_enabled()) { std::cerr << msg; } } while(0)
```

### What Gets Logged

- FFI initialization
- External class registration
- Kernel startup
- Message polling
- Execution flow
- Environment transitions
- Mutex operations
- Memory allocations

## Testing

### Unit Tests

```python
# test_clean_output.py
def test_info_output():
    execute('#eval IO.println "Hello"')
    assert result == "Hello"  # Not JSON!

def test_error_output():
    execute('def broken := 1 + "string"')
    assert "severity" in result  # Full JSON with error details
```

### Manual Testing

```bash
# Build
./build.sh
lake build xlean

# Test directly
python3 test_clean_output.py

# Test in Jupyter
jupyter lab
# Create notebook, select Lean 4 kernel
```

## Performance Notes

**Startup:**
- Lean runtime init: ~50ms
- xeus kernel init: ~50ms
- Total: ~100ms

**Execution:**
- FFI call overhead: <1ms
- Mutex lock/unlock: <0.1ms
- JSON parsing: ~1ms for typical message
- Lean elaboration: Varies (dominant cost)

**Memory:**
- Base Lean runtime: ~30MB
- xeus libraries: ~20MB
- Environment: Grows with definitions
- Total baseline: ~50MB

## Known Issues

1. **REPL Elaborator Limitations**
   - Some infix operators not supported
   - Workaround: Use explicit function calls

2. **No Tab Completion**
   - Not yet implemented
   - Need to query Lean environment

3. **No Inspection**
   - No Shift+Tab support
   - Need to implement inspect_request

4. **Static Linking Required**
   - Shared library doesn't work
   - Increases binary size

## Future Work

### Short Term
- [ ] Implement completion (query Lean environment)
- [ ] Implement inspection
- [ ] Add kernel.json installation script
- [ ] Improve error formatting

### Medium Term
- [ ] LaTeX rendering for proof goals
- [ ] Better syntax highlighting
- [ ] File loading support
- [ ] Mathlib integration testing

### Long Term
- [ ] Investigate shared library issue
- [ ] Windows support
- [ ] Performance optimization
- [ ] Rich display protocols

## Conclusion

The Lean-owned event loop architecture provides:
- **Clean integration** with Lean's runtime
- **Good performance** with direct FFI calls
- **Simple deployment** (single binary)
- **Easy debugging** (single process)
- **Proper memory management** (Lean GC)

Key insight: **Inverting control** (Lean calls C++, not C++ calls Lean) simplifies the architecture and avoids complex subprocess management while maintaining full access to Lean's capabilities.
