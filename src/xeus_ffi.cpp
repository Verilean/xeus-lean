/*
Copyright (c) 2025, xeus-lean contributors
Released under Apache 2.0 license as described in the file LICENSE.

C++ FFI wrapper for xeus - called from Lean
*/

#include <iostream>
#include <memory>
#include <string>
#include <queue>
#include <mutex>
#include <thread>
#include <chrono>

#include <lean/lean.h>
#include "nlohmann/json.hpp"
#include "xeus/xkernel.hpp"
#include "xeus/xkernel_configuration.hpp"
#include "xeus/xhelper.hpp"
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

// Simple interpreter that queues messages for Lean to process
class lean_interpreter : public xeus::xinterpreter {
public:
    lean_interpreter() : m_message_mutex(), m_should_stop(false), m_current_callback(nullptr) {
        DEBUG_LOG("[C++ FFI] lean_interpreter constructed, mutex at " << (void*)&m_message_mutex);
    }
    virtual ~lean_interpreter() = default;

    void configure_impl() override {
        DEBUG_LOG("[C++ FFI] Interpreter configured");
    }

    void execute_request_impl(send_reply_callback cb,
                              int execution_count,
                              const std::string& code,
                              xeus::execute_request_config config,
                              nl::json /* user_expressions */) override {
        DEBUG_LOG("[C++ FFI] Execute request: " << code);

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
        return xeus::create_info_reply(
            "",
            "xlean",
            "0.1.0",
            "lean",
            "4.0",
            "text/x-lean",
            ".lean",
            "",
            "",
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

            // Try to parse as JSON first
            try {
                auto result = json::parse(result_json);
                // If it's valid JSON, pretty-print it
                pub_data["text/plain"] = result.dump(2);
            } catch (const json::parse_error&) {
                // Not JSON, use as plain text
                pub_data["text/plain"] = result_json;
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

private:
    std::queue<std::string> m_message_queue;
    std::mutex m_message_mutex;
    bool m_should_stop = false;
    send_reply_callback m_current_callback;
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

}  // extern "C"
