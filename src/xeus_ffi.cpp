/*
Copyright (c) 2025, xeus-lean contributors
Released under Apache 2.0 license as described in the file LICENSE.

C++ FFI wrapper for xeus - called from Lean
*/

#include <iostream>
#include <memory>
#include <string>
#include <queue>
#include <map>
#include <mutex>
#include <thread>
#include <chrono>
#include <atomic>
#include <fcntl.h>
#include <unistd.h>

#include <lean/lean.h>
#include "nlohmann/json.hpp"
#include "xeus/xkernel.hpp"
#include "xeus/xkernel_configuration.hpp"
#include "xeus/xhelper.hpp"
#include "xeus/xcomm.hpp"
#include "xeus/xguid.hpp"
#include "xeus-zmq/xserver_zmq.hpp"
#include "xeus-zmq/xzmq_context.hpp"

using json = nlohmann::json;

namespace {

// Check if debug mode is enabled via environment variable
inline bool is_debug_enabled() {
    static bool debug = []() {
        const char* env = std::getenv("XLEAN_DEBUG");
        return env != nullptr && (std::string(env) == "1" || std::string(env) == "true");
    }();
    return debug;
}

// Debug logging macro
#define DEBUG_LOG(msg) do { if (is_debug_enabled()) { std::cerr << msg << std::endl; } } while(0)

// Walk `text` and pull out MIME-typed payloads emitted by Lean's Display
// module. Each payload is encoded as
//
//     \x1bMIME:<mime-type>\x1e<content>\x1b/MIME\x1e
//
// where \x1b is ESC (0x1B) and \x1e is RS (0x1E). ESC does not appear in
// ordinary Lean output, so it is safe as a sentinel. Anything outside
// payloads is appended to `plain_out` so we don't drop ordinary
// `IO.println` / `#eval` output. (Same encoding the WASM kernel parses
// in xinterpreter_wasm.cpp.)
static void extract_mime_payloads(const std::string& text,
                                  json& bundle,
                                  std::string& plain_out)
{
    static const std::string OPEN_PREFIX = "\x1b" "MIME:";
    static const std::string CLOSE_MARK  = "\x1b" "/MIME" "\x1e";
    static const char RS = '\x1e';

    std::size_t cursor = 0;
    while (cursor < text.size()) {
        std::size_t open = text.find(OPEN_PREFIX, cursor);
        if (open == std::string::npos) {
            plain_out.append(text, cursor, std::string::npos);
            return;
        }
        plain_out.append(text, cursor, open - cursor);
        std::size_t mime_start = open + OPEN_PREFIX.size();
        std::size_t rs_pos = text.find(RS, mime_start);
        if (rs_pos == std::string::npos) {
            plain_out.append(text, open, std::string::npos);
            return;
        }
        std::string mime_type = text.substr(mime_start, rs_pos - mime_start);
        std::size_t content_start = rs_pos + 1;
        std::size_t close_pos = text.find(CLOSE_MARK, content_start);
        if (close_pos == std::string::npos) {
            plain_out.append(text, open, std::string::npos);
            return;
        }
        bundle[mime_type] = text.substr(content_start, close_pos - content_start);
        cursor = close_pos + CLOSE_MARK.size();
    }
}

// Simple interpreter that queues messages for Lean to process
class lean_interpreter : public xeus::xinterpreter {
public:
    lean_interpreter() : m_message_mutex(), m_should_stop(false), m_current_callback(nullptr) {
        DEBUG_LOG("[C++ FFI] lean_interpreter constructed, mutex at " << (void*)&m_message_mutex);
    }
    virtual ~lean_interpreter() = default;

    void configure_impl() override {
        DEBUG_LOG("[C++ FFI] Interpreter configured");
        // Register a single comm target named "xlean". JS frontends open a
        // comm channel against this target and the per-channel `on_message`
        // handler queues incoming messages for the Lean side to process
        // (see poll_comm / send_comm).
        comm_manager().register_comm_target(
            "xlean",
            [this](xeus::xcomm&& comm, xeus::xmessage open_request) {
                xeus::xguid id = comm.id();
                DEBUG_LOG("[C++ FFI] comm_open id=" << std::string(id.c_str()));

                // Move the comm into our owned map. We need to keep it alive
                // so we can call .send() on it later — xeus would otherwise
                // drop it after this callback returns.
                {
                    std::lock_guard<std::mutex> lock(m_comm_mutex);
                    auto [it, inserted] = m_comms.emplace(id, std::move(comm));
                    // Register the per-comm message handler against the
                    // stored xcomm (the one in `comm_request` was moved out).
                    it->second.on_message(
                        [this, id](xeus::xmessage msg) {
                            json ev;
                            ev["op"] = "msg";
                            ev["id"] = std::string(id.c_str());
                            ev["data"] = msg.content().value("data", nl::json::object());
                            std::lock_guard<std::mutex> lock(m_comm_mutex);
                            m_comm_event_queue.push(ev.dump());
                        });
                    it->second.on_close(
                        [this, id](xeus::xmessage /* msg */) {
                            json ev;
                            ev["op"] = "close";
                            ev["id"] = std::string(id.c_str());
                            std::lock_guard<std::mutex> lock(m_comm_mutex);
                            m_comm_event_queue.push(ev.dump());
                            m_comms.erase(id);
                        });
                }
                // Queue the open event with any payload the JS side sent.
                json ev;
                ev["op"] = "open";
                ev["id"] = std::string(id.c_str());
                ev["data"] = open_request.content().value("data", nl::json::object());
                std::lock_guard<std::mutex> lock(m_comm_mutex);
                m_comm_event_queue.push(ev.dump());
            });
    }

    void execute_request_impl(send_reply_callback cb,
                              int execution_count,
                              const std::string& code,
                              xeus::execute_request_config config,
                              nl::json /* user_expressions */) override {
        DEBUG_LOG("[C++ FFI] Execute request: " << code);

        // Redirect stdout into a pipe so we can capture writes that go
        // straight to fd 1 — including `IO.println` calls inside elab
        // macros (e.g. Sparkle's `#synthesizeVerilog`) that bypass
        // Lean's `withIsolatedStreams` capture in `#eval`. Stderr is
        // intentionally left alone so XLEAN_DEBUG-style logs still
        // reach the kernel terminal.
        begin_stdout_capture();

        // Queue this message for Lean to process
        std::lock_guard<std::mutex> lock(m_message_mutex);

        json msg;
        msg["msg_type"] = "execute_request";
        msg["content"]["code"] = code;
        msg["content"]["execution_count"] = execution_count;

        m_message_queue.push(msg.dump());
        m_current_callback = cb;

        // Don't send reply now - Lean will call send_result/send_error later
    }

    nl::json complete_request_impl(const std::string& /* code */,
                                   int /* cursor_pos */) override {
        return xeus::create_complete_reply({}, 0, 0);
    }

    nl::json inspect_request_impl(const std::string& /* code */,
                                  int /* cursor_pos */,
                                  int /* detail_level */) override {
        return xeus::create_inspect_reply(false);
    }

    nl::json is_complete_request_impl(const std::string& /* code */) override {
        return xeus::create_is_complete_reply("complete");
    }

    nl::json kernel_info_request_impl() override {
        // No CodeMirror mode for Lean ships with JupyterLab, but Lean's
        // surface syntax overlaps with Haskell enough that the haskell
        // mode is a passable approximation (highlights `let`, `do`,
        // `fun`, `import`, operators, comments). pygments has a real
        // Lean lexer (`lean`) so any nbconvert/nbviewer rendering uses
        // accurate highlighting.
        return xeus::create_info_reply(
            "",
            "xlean",
            "0.1.0",
            "lean",
            "4.0",
            "text/x-haskell",   // mimetype — picked up by CodeMirror
            ".lean",
            "lean",             // pygments_lexer (used by nbconvert)
            "haskell",          // codemirror_mode (used by JupyterLab)
            "Lean 4 Jupyter Kernel"
        );
    }

    void shutdown_request_impl() override {
        DEBUG_LOG("[C++ FFI] Shutdown requested");
        m_should_stop = true;
    }

    // Methods for Lean to call
    std::string poll_message() {
        DEBUG_LOG("[C++ FFI] poll_message called, this=" << (void*)this);
        DEBUG_LOG("[C++ FFI] About to lock mutex at " << (void*)&m_message_mutex);
        try {
            std::lock_guard<std::mutex> lock(m_message_mutex);
            DEBUG_LOG("[C++ FFI] Mutex locked successfully");
            if (m_message_queue.empty()) {
                return "";
            }
            std::string msg = m_message_queue.front();
            m_message_queue.pop();
            return msg;
        } catch (const std::exception& e) {
            DEBUG_LOG("[C++ FFI] Exception in poll_message: " << e.what());
            throw;
        }
    }

    void send_result(int execution_count, const std::string& result_json) {
        try {
            nl::json pub_data;

            // Drain anything that elab-time IO.println wrote to fd 1
            // since execute_request_impl began. This is what makes
            // plain `IO.println "..."` from inside an `elab` macro
            // appear in the cell output even though Lean's #eval
            // capture path doesn't see it.
            std::string captured = end_stdout_capture();

            // First pass: pull MIME payloads (Display.html/.svg/.waveform/...)
            // out of the captured stdout AND the result string, leaving
            // ordinary `#eval` / `IO.println` text behind in `plain`.
            //
            // Both channels carry MIME markers in practice:
            //   - `result_json` is what Lean's message log produced via
            //     `logInfo` / `logInfoAt` (xeus-lean's `Display.html`
            //     etc. all go through this path inside an `elab`).
            //   - `captured` is whatever Lean's `IO.println` wrote
            //     directly to stdout from inside an `elab`/`#eval`
            //     command.  Downstream packages (e.g. Sparkle.Display)
            //     emit MIME markers from `IO.println` so a single
            //     `#eval Sparkle.Display.Diagram.blockDiagram d` can
            //     produce a rendered SVG cell.  Without this scan
            //     those bytes would be forwarded as raw text and the
            //     marker would show up as a literal `MIME:image/...`
            //     string.
            std::string plain_captured;
            extract_mime_payloads(captured, pub_data, plain_captured);
            std::string plain;
            extract_mime_payloads(result_json, pub_data, plain);

            // Prepend the (now MIME-stripped) captured stdout. We do
            // this *before* the pre-formatted Lean messages so the
            // order matches what happened: elab-time prints first,
            // then the result text.
            if (!plain_captured.empty()) {
                if (!plain.empty() && plain_captured.back() != '\n') {
                    plain_captured.push_back('\n');
                }
                plain = plain_captured + plain;
            }

            if (!plain.empty()) {
                // Trim a single trailing newline added by IO.println so the
                // cell output isn't padded with an extra blank line.
                if (plain.back() == '\n') plain.pop_back();
                pub_data["text/plain"] = plain;
            } else if (pub_data.empty()) {
                // No MIME markers and no plain text — keep the legacy
                // behavior of trying to parse the whole string as JSON
                // (used by the older error-dump path; harmless otherwise).
                try {
                    auto result = json::parse(result_json);
                    if (result.is_object() &&
                        (result.contains("text/html") || result.contains("image/svg+xml"))) {
                        pub_data = result;
                    } else {
                        pub_data["text/plain"] = result.is_string()
                            ? result.get<std::string>() : result.dump(2);
                    }
                } catch (const json::parse_error&) {
                    pub_data["text/plain"] = result_json;
                }
            }

            publish_execution_result(execution_count, std::move(pub_data), nl::json::object());

            // Send successful reply to callback
            if (m_current_callback) {
                m_current_callback(xeus::create_successful_reply());
                m_current_callback = nullptr;
            }

            DEBUG_LOG("[C++ FFI] Result sent");
        } catch (const std::exception& e) {
            std::cerr << "[C++ FFI] Error sending result: " << e.what() << std::endl;
        }
    }

    void send_error(int execution_count, const std::string& error_json) {
        try {
            // Make sure we don't leak the fd 1 redirect into the next
            // cell. We drop the captured bytes — error path already has
            // a structured payload and there's no good place to slot
            // raw stdout in.
            (void)end_stdout_capture();

            auto error = json::parse(error_json);
            std::string error_msg = error.dump(2);

            publish_execution_error("LeanError", error_msg, {error_msg});

            // Send error reply to callback
            if (m_current_callback) {
                nl::json err_reply = xeus::create_error_reply(error_msg, "LeanError", nl::json::array());
                m_current_callback(std::move(err_reply));
                m_current_callback = nullptr;
            }

            DEBUG_LOG("[C++ FFI] Error sent");
        } catch (const std::exception& e) {
            std::cerr << "[C++ FFI] Error sending error: " << e.what() << std::endl;
        }
    }

    bool should_stop() const {
        return m_should_stop;
    }

    /** Save fd 1, create a pipe, dup the write end onto fd 1. After
        this returns, anything written to stdout (printf, fputs,
        IO.println from Lean elab time, ...) goes into the pipe. Idempotent
        within a single execute_request — calling twice is harmless because
        we only set up the pipe if `m_stdout_pipe_r == -1`. */
    void begin_stdout_capture() {
        if (m_stdout_pipe_r != -1) return;  // already capturing
        int p[2];
        if (pipe(p) != 0) {
            DEBUG_LOG("[C++ FFI] pipe() failed; skipping stdout capture");
            return;
        }
        // Make the read end non-blocking so end_stdout_capture's drain
        // returns instead of waiting for EOF.
        int flags = fcntl(p[0], F_GETFL, 0);
        fcntl(p[0], F_SETFL, flags | O_NONBLOCK);
        m_saved_stdout_fd = dup(STDOUT_FILENO);
        if (m_saved_stdout_fd < 0) {
            close(p[0]); close(p[1]);
            return;
        }
        // Make sure C stdout buffer is flushed before we redirect, so the
        // captured bytes really come from this cell.
        std::fflush(stdout);
        dup2(p[1], STDOUT_FILENO);
        close(p[1]);
        m_stdout_pipe_r = p[0];
    }

    /** Drain the pipe, restore fd 1, close the pipe. Returns whatever
        was buffered. Empty string if capture wasn't active. */
    std::string end_stdout_capture() {
        if (m_stdout_pipe_r == -1) return "";
        // Flush anything Lean's runtime still has in C-level buffers
        // before we yank the fd back.
        std::fflush(stdout);
        std::string out;
        char buf[4096];
        while (true) {
            ssize_t n = read(m_stdout_pipe_r, buf, sizeof(buf));
            if (n > 0) out.append(buf, buf + n);
            else break;
        }
        // Restore the real stdout.
        if (m_saved_stdout_fd >= 0) {
            dup2(m_saved_stdout_fd, STDOUT_FILENO);
            close(m_saved_stdout_fd);
            m_saved_stdout_fd = -1;
        }
        close(m_stdout_pipe_r);
        m_stdout_pipe_r = -1;
        return out;
    }

    /** Pop one queued comm event (open/msg/close) as JSON, or "" if empty. */
    std::string poll_comm() {
        std::lock_guard<std::mutex> lock(m_comm_mutex);
        if (m_comm_event_queue.empty()) return "";
        std::string ev = m_comm_event_queue.front();
        m_comm_event_queue.pop();
        return ev;
    }

    /**
     * Send a JSON message back to the JS side over the comm identified by
     * `comm_id_hex`. Returns true on success, false if the comm has been
     * closed or never existed.
     */
    bool send_comm(const std::string& comm_id_hex, const std::string& data_json) {
        xeus::xguid id;
        // xfixed_string<55> assignment from std::string truncates if too long;
        // comm ids are 32-char hex so this fits comfortably.
        id = comm_id_hex.c_str();
        std::lock_guard<std::mutex> lock(m_comm_mutex);
        auto it = m_comms.find(id);
        if (it == m_comms.end()) return false;
        try {
            nl::json data = nl::json::parse(data_json);
            it->second.send(nl::json::object(), std::move(data), {});
            return true;
        } catch (const std::exception& e) {
            DEBUG_LOG("[C++ FFI] send_comm failed: " << e.what());
            return false;
        }
    }

private:
    std::queue<std::string> m_message_queue;
    std::mutex m_message_mutex;
    bool m_should_stop = false;
    send_reply_callback m_current_callback;

    // Comm channels we've taken ownership of. Keyed by guid; the xcomm
    // value lives here so its on_message handler stays alive across calls.
    std::map<xeus::xguid, xeus::xcomm> m_comms;
    std::queue<std::string> m_comm_event_queue;
    std::mutex m_comm_mutex;

    // Stdout fd-capture machinery. -1 when no capture is active.
    int m_stdout_pipe_r = -1;
    int m_saved_stdout_fd = -1;
};

// Global kernel state
struct KernelState {
    std::unique_ptr<xeus::xcontext> context;
    lean_interpreter* interpreter;  // Raw pointer - owned by kernel
    std::unique_ptr<xeus::xkernel> kernel;
    std::thread kernel_thread;
};

}  // namespace

// Memory management for Lean external objects
extern "C" {

// Finalizer called by Lean's GC when KernelHandle is collected
extern "C" void finalize_kernel_state(void* ptr) {
    DEBUG_LOG("[C++ FFI] Finalizing kernel state");
    auto* state = static_cast<KernelState*>(ptr);

    // Stop and join kernel thread
    if (state->kernel_thread.joinable()) {
        state->kernel_thread.join();
    }

    // Delete the state (unique_ptrs will automatically clean up)
    delete state;
}

// External class registration for KernelState
static lean_external_class* g_kernel_state_class = nullptr;

static lean_external_class* get_kernel_state_class() {
    if (g_kernel_state_class == nullptr) {
        DEBUG_LOG("[C++ FFI] About to call lean_register_external_class, finalizer=" << (void*)finalize_kernel_state);
        g_kernel_state_class = lean_register_external_class(
            finalize_kernel_state,  // finalizer
            nullptr                  // foreach (not needed)
        );
        DEBUG_LOG("[C++ FFI] lean_register_external_class returned: " << (void*)g_kernel_state_class);
    }
    return g_kernel_state_class;
}

// Extract KernelState pointer from Lean external object
static inline KernelState* to_kernel_state(lean_object* obj) {
    return static_cast<KernelState*>(lean_get_external_data(obj));
}

// FFI functions callable from Lean

// Initialize the FFI (must be called before using the kernel)
lean_object* xeus_ffi_initialize(lean_object* /* world */) {
    DEBUG_LOG("[C++ FFI] Initializing FFI, registering external class");
    // Force registration of the external class
    get_kernel_state_class();
    DEBUG_LOG("[C++ FFI] FFI initialized");
    return lean_io_result_mk_ok(lean_box(0));
}

// Initialize kernel
lean_object* xeus_kernel_init(lean_object* connection_file_obj, lean_object* /* world */) {
    DEBUG_LOG("[C++ FFI] xeus_kernel_init called");
    try {
        std::string connection_file = lean_string_cstr(connection_file_obj);

        DEBUG_LOG("[C++ FFI] Initializing kernel with: " << connection_file);

        // Load configuration
        xeus::xconfiguration config = xeus::load_configuration(connection_file);

        // Create kernel state
        auto* state = new KernelState();

        // Create ZMQ context
        state->context = xeus::make_zmq_context();

        // Create interpreter as unique_ptr for kernel to own
        auto interpreter_ptr = std::make_unique<lean_interpreter>();
        state->interpreter = interpreter_ptr.get();  // Keep raw pointer for our use
        DEBUG_LOG("[C++ FFI] Created interpreter at " << (void*)state->interpreter);

        // Create kernel (takes ownership of interpreter)
        DEBUG_LOG("[C++ FFI] Creating xkernel with interpreter at " << (void*)interpreter_ptr.get());
        state->kernel = std::make_unique<xeus::xkernel>(
            config,
            xeus::get_user_name(),
            std::move(state->context),
            std::move(interpreter_ptr),  // Kernel takes ownership
            xeus::make_xserver_default
        );
        DEBUG_LOG("[C++ FFI] xkernel created, interpreter pointer in state: " << (void*)state->interpreter);

        // Start kernel in background thread
        state->kernel_thread = std::thread([kernel_ptr = state->kernel.get()]() {
            DEBUG_LOG("[C++ FFI] Kernel thread started");
            kernel_ptr->start();
            DEBUG_LOG("[C++ FFI] Kernel thread stopped");
        });

        // Give kernel time to start
        std::this_thread::sleep_for(std::chrono::milliseconds(100));

        // Return handle as external object (Lean's GC will manage it)
        DEBUG_LOG("[C++ FFI] Creating external object for kernel state at " << (void*)state);
        DEBUG_LOG("[C++ FFI] About to call get_kernel_state_class()");
        auto* ext_class = get_kernel_state_class();
        DEBUG_LOG("[C++ FFI] External class: " << (void*)ext_class);

        if (ext_class == nullptr) {
            std::cerr << "[C++ FFI] ERROR: External class is null!" << std::endl;
            throw std::runtime_error("External class registration failed");
        }

        DEBUG_LOG("[C++ FFI] About to call lean_alloc_external");
        lean_object* handle = lean_alloc_external(ext_class, state);
        DEBUG_LOG("[C++ FFI] External object created: " << (void*)handle);

        lean_object* some_result = lean_alloc_ctor(1, 1, 0);  // some
        lean_ctor_set(some_result, 0, handle);
        DEBUG_LOG("[C++ FFI] Returning Some(handle)");

        return lean_io_result_mk_ok(some_result);

    } catch (const std::exception& e) {
        std::cerr << "[C++ FFI] Kernel init failed: " << e.what() << std::endl;

        lean_object* none_result = lean_box(0);  // none
        return lean_io_result_mk_ok(none_result);
    }
}

// Poll for messages
lean_object* xeus_kernel_poll(lean_object* handle_obj, uint32_t timeout_ms, lean_object* /* world */) {
    try {
        auto* state = to_kernel_state(handle_obj);

        DEBUG_LOG("[C++ FFI] Poll: state=" << (void*)state << ", interpreter=" << (void*)state->interpreter);

        if (!state || !state->interpreter) {
            DEBUG_LOG("[C++ FFI] Poll: Invalid state or interpreter");
            return lean_io_result_mk_ok(lean_mk_string(""));
        }

        // Poll for message
        DEBUG_LOG("[C++ FFI] Calling poll_message on interpreter");
        std::string msg = state->interpreter->poll_message();

        if (msg.empty()) {
            // Small delay
            std::this_thread::sleep_for(std::chrono::milliseconds(timeout_ms));
        }

        lean_object* result = lean_mk_string(msg.c_str());
        return lean_io_result_mk_ok(result);

    } catch (const std::exception& e) {
        std::cerr << "[C++ FFI] Poll failed: " << e.what() << std::endl;
        return lean_io_result_mk_ok(lean_mk_string(""));
    }
}

// Send result
lean_object* xeus_kernel_send_result(lean_object* handle_obj, uint32_t exec_count,
                                     lean_object* result_obj, lean_object* /* world */) {
    try {
        auto* state = to_kernel_state(handle_obj);

        if (state && state->interpreter) {
            std::string result = lean_string_cstr(result_obj);
            state->interpreter->send_result(exec_count, result);
        }

        lean_object* unit = lean_box(0);
        return lean_io_result_mk_ok(unit);

    } catch (const std::exception& e) {
        std::cerr << "[C++ FFI] Send result failed: " << e.what() << std::endl;
        lean_object* unit = lean_box(0);
        return lean_io_result_mk_ok(unit);
    }
}

// Send error
lean_object* xeus_kernel_send_error(lean_object* handle_obj, uint32_t exec_count,
                                    lean_object* error_obj, lean_object* /* world */) {
    try {
        auto* state = to_kernel_state(handle_obj);

        if (state && state->interpreter) {
            std::string error = lean_string_cstr(error_obj);
            state->interpreter->send_error(exec_count, error);
        }

        lean_object* unit = lean_box(0);
        return lean_io_result_mk_ok(unit);

    } catch (const std::exception& e) {
        std::cerr << "[C++ FFI] Send error failed: " << e.what() << std::endl;
        lean_object* unit = lean_box(0);
        return lean_io_result_mk_ok(unit);
    }
}

// Check if should stop
lean_object* xeus_kernel_should_stop(lean_object* handle_obj, lean_object* /* world */) {
    try {
        auto* state = to_kernel_state(handle_obj);

        if (state && state->interpreter) {
            bool should_stop = state->interpreter->should_stop();
            lean_object* result = lean_box(should_stop ? 1 : 0);
            return lean_io_result_mk_ok(result);
        }

        lean_object* result = lean_box(0);
        return lean_io_result_mk_ok(result);

    } catch (const std::exception& e) {
        std::cerr << "[C++ FFI] Should stop check failed: " << e.what() << std::endl;
        lean_object* result = lean_box(0);
        return lean_io_result_mk_ok(result);
    }
}

// Pop one queued comm event ({op:"open"|"msg"|"close",id:..,data?:..}) as JSON.
// Returns "" when the queue is empty.
lean_object* xeus_kernel_poll_comm(lean_object* handle_obj, lean_object* /* world */) {
    try {
        auto* state = to_kernel_state(handle_obj);
        std::string ev;
        if (state && state->interpreter) {
            ev = state->interpreter->poll_comm();
        }
        return lean_io_result_mk_ok(lean_mk_string(ev.c_str()));
    } catch (const std::exception& e) {
        std::cerr << "[C++ FFI] poll_comm failed: " << e.what() << std::endl;
        return lean_io_result_mk_ok(lean_mk_string(""));
    }
}

// Send a JSON message to the JS side over a previously-opened comm channel.
// Returns 1 on success, 0 if the comm id is unknown or send failed.
lean_object* xeus_kernel_send_comm(lean_object* handle_obj,
                                   lean_object* comm_id_obj,
                                   lean_object* data_obj,
                                   lean_object* /* world */) {
    try {
        auto* state = to_kernel_state(handle_obj);
        std::string id = lean_string_cstr(comm_id_obj);
        std::string data = lean_string_cstr(data_obj);
        bool ok = false;
        if (state && state->interpreter) {
            ok = state->interpreter->send_comm(id, data);
        }
        return lean_io_result_mk_ok(lean_box(ok ? 1 : 0));
    } catch (const std::exception& e) {
        std::cerr << "[C++ FFI] send_comm failed: " << e.what() << std::endl;
        return lean_io_result_mk_ok(lean_box(0));
    }
}

}  // extern "C"
