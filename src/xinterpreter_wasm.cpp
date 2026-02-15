/***************************************************************************
* Copyright (c) 2025, xeus-lean contributors
*
* Distributed under the terms of the Apache Software License 2.0.
*
* The full license is in the file LICENSE, distributed with this software.
****************************************************************************/

#include <iostream>
#include <string>
#include <sstream>
#include <unordered_set>
#include <unordered_map>
#include <stdexcept>

#ifdef __EMSCRIPTEN__
#include <emscripten/stack.h>
#endif

#include "xeus-lean/xinterpreter_wasm.hpp"
#include "xeus/xhelper.hpp"

#include <lean/lean.h>

namespace xeus_lean
{

// Diagnostic: test that hash tables work in wasm64
static void test_hash_tables() {
    std::cerr << "[WASM] test_hash_tables: sizeof(size_t)=" << sizeof(size_t)
              << " sizeof(void*)=" << sizeof(void*) << std::endl;
    try {
        // Test 1: basic unordered_set<int>
        std::unordered_set<int> s;
        for (int i = 0; i < 10000; i++) s.insert(i);
        std::cerr << "[WASM] test_hash_tables: unordered_set<int> size=" << s.size()
                  << " buckets=" << s.bucket_count() << std::endl;

        // Test 2: unordered_map<void*, void*> (like lean's m_cache)
        std::unordered_map<void*, void*> m;
        for (int i = 0; i < 10000; i++) {
            m[(void*)(uintptr_t)(i * 8)] = (void*)(uintptr_t)i;
        }
        std::cerr << "[WASM] test_hash_tables: unordered_map<void*,void*> size=" << m.size()
                  << " buckets=" << m.bucket_count() << std::endl;

        // Test 3: unordered_set with custom hash (like lean's sharecommon)
        struct ptr_hash {
            std::size_t operator()(void* p) const { return (std::size_t)p; }
        };
        struct ptr_eq {
            std::size_t operator()(void* a, void* b) const { return a == b; }  // returns size_t like lean
        };
        std::unordered_set<void*, ptr_hash, ptr_eq> cs;
        for (int i = 0; i < 10000; i++) {
            cs.insert((void*)(uintptr_t)(i * 16));
        }
        std::cerr << "[WASM] test_hash_tables: custom set size=" << cs.size()
                  << " buckets=" << cs.bucket_count() << std::endl;

        std::cerr << "[WASM] test_hash_tables: ALL PASSED" << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "[WASM] test_hash_tables: FAILED: " << e.what() << std::endl;
    }
}

// Forward declarations for Lean-exported functions.
// These symbols are provided by the Lean libraries (Init, REPL, etc.)
// compiled to WASM via: .lean -> .c (lake) -> .wasm.o (emcc)
extern "C" {
    // Lean runtime initialization (not in public lean.h)
    void lean_initialize_runtime_module(void);

    // Full Lean initialization: runtime + C++ util/kernel/library modules +
    // Init/Std/Lean module inits. This is REQUIRED to set up C++ global state
    // (name tables, expression caches, etc.) that hash tables depend on.
    // Without this, processHeader triggers __next_prime overflow in libc++.
    void lean_initialize(void);

    // REPL module initialization (not covered by lean_initialize)
    // Note: Lean 4 compiler erases the IO world token from generated C code.
    // These functions take only `builtin`, not `(builtin, world)`.
    lean_object* initialize_xeus_x2dlean_REPL(uint8_t builtin);
    lean_object* initialize_xeus_x2dlean_REPL_Main(uint8_t builtin);
    lean_object* initialize_xeus_x2dlean_WasmRepl(uint8_t builtin);

    // Exported from src/WasmRepl.lean via @[export]
    // World token is erased — these match the actual signatures in WasmRepl.c
    lean_object* lean_wasm_repl_init();
    lean_object* lean_wasm_repl_create_state();
    lean_object* lean_wasm_repl_execute(lean_object* state_ref,
                                        lean_object* code,
                                        uint32_t env_id,
                                        uint8_t has_env);
}

interpreter::interpreter()
    : m_initialized(false)
    , m_current_env(-1)
    , m_repl_state(nullptr)
{
}

interpreter::~interpreter()
{
    if (m_repl_state) {
        lean_dec(static_cast<lean_object*>(m_repl_state));
        m_repl_state = nullptr;
    }
}

bool interpreter::initialize_lean_runtime()
{
    if (m_initialized) return true;

    try {
        // Initialize Lean runtime + task manager (0 workers for single-threaded WASM)
        lean_initialize_runtime_module();
        lean_init_task_manager_using(0);

        // Full Lean initialization: C++ util/kernel/library modules + Init/Std/Lean.
        // This sets up critical C++ global state (name hash tables, expression caches,
        // type checker state) that must be initialized before processHeader runs.
        // Using lean_initialize() instead of bare initialize_Init(1) matches
        // the working test_wasm_node initialization sequence.
        lean_initialize();

        // Initialize REPL modules (not covered by lean_initialize)
        lean_object* res;

        res = initialize_xeus_x2dlean_REPL(1);
        if (lean_io_result_is_error(res)) {
            std::cerr << "[WASM] Failed to initialize REPL module" << std::endl;
            lean_dec(res);
            return false;
        }
        lean_dec(res);

        res = initialize_xeus_x2dlean_REPL_Main(1);
        if (lean_io_result_is_error(res)) {
            std::cerr << "[WASM] Failed to initialize REPL.Main module" << std::endl;
            lean_dec(res);
            return false;
        }
        lean_dec(res);

        res = initialize_xeus_x2dlean_WasmRepl(1);
        if (lean_io_result_is_error(res)) {
            std::cerr << "[WASM] Failed to initialize WasmRepl module" << std::endl;
            lean_dec(res);
            return false;
        }
        lean_dec(res);

        lean_io_mark_end_initialization();

        // Initialize search path
        res = lean_wasm_repl_init();
        if (lean_io_result_is_error(res)) {
            std::cerr << "[WASM] Failed to initialize REPL" << std::endl;
            lean_dec(res);
            return false;
        }
        lean_dec(res);

        // Create REPL state (IO.Ref State)
        res = lean_wasm_repl_create_state();
        if (lean_io_result_is_error(res)) {
            std::cerr << "[WASM] Failed to create REPL state" << std::endl;
            lean_dec(res);
            return false;
        }
        lean_object* state_ref = lean_io_result_get_value(res);
        lean_inc(state_ref);
        m_repl_state = state_ref;
        lean_dec(res);

        m_initialized = true;
        std::cerr << "[WASM] Lean runtime initialized successfully" << std::endl;
        return true;

    } catch (const std::exception& e) {
        std::cerr << "[WASM] Exception during initialization: " << e.what() << std::endl;
        return false;
    }
}

std::string interpreter::call_lean_repl(const std::string& code, int env)
{
    std::cerr << "[WASM] call_lean_repl: ENTER code='" << code.substr(0, 50) << "' env=" << env << std::endl;

    if (!m_repl_state) {
        std::cerr << "[WASM] call_lean_repl: REPL not initialized!" << std::endl;
        return "{\"message\": \"REPL not initialized\"}";
    }

    std::cerr << "[WASM] call_lean_repl: creating string object" << std::endl;
    lean_object* code_obj = lean_mk_string(code.c_str());

    std::cerr << "[WASM] call_lean_repl: preparing state_ref" << std::endl;
    lean_object* state_ref = static_cast<lean_object*>(m_repl_state);
    lean_inc(state_ref);

    uint8_t has_env = (env >= 0) ? 1 : 0;
    uint32_t env_id = (env >= 0) ? static_cast<uint32_t>(env) : 0;
    std::cerr << "[WASM] call_lean_repl: calling lean_wasm_repl_execute (has_env=" << (int)has_env << " env_id=" << env_id << ")" << std::endl;

    lean_object* res;
    try {
        res = lean_wasm_repl_execute(state_ref, code_obj, env_id, has_env);
    } catch (const std::exception& e) {
        std::cerr << "[WASM] call_lean_repl: C++ EXCEPTION: " << e.what() << std::endl;
        return "{\"error\": \"C++ exception: " + std::string(e.what()) + "\"}";
    }

    std::cerr << "[WASM] call_lean_repl: lean_wasm_repl_execute returned" << std::endl;

    if (lean_io_result_is_error(res)) {
        std::cerr << "[WASM] call_lean_repl: execution returned error" << std::endl;
        lean_io_result_show_error(res);
        lean_dec(res);
        return "{\"error\": \"Lean REPL execution failed\"}";
    }

    lean_object* result = lean_io_result_get_value(res);
    const char* result_str = lean_string_cstr(result);
    std::string output = result_str ? result_str : "";
    std::cerr << "[WASM] call_lean_repl: result='" << output.substr(0, 200) << "'" << std::endl;
    lean_dec(res);

    return output;
}

void interpreter::configure_impl()
{
    std::cerr << "[WASM] configure_impl: ENTER" << std::endl;
    test_hash_tables();
    initialize_lean_runtime();
    std::cerr << "[WASM] configure_impl: EXIT" << std::endl;
}

void interpreter::execute_request_impl(send_reply_callback cb,
                                        int execution_counter,
                                        const std::string& code,
                                        xeus::execute_request_config /*config*/,
                                        nl::json /*user_expressions*/)
{
    std::cerr << "[WASM] execute_request_impl: ENTER (code=" << code.substr(0, 50) << ")" << std::endl;
    if (!m_initialized) {
        if (!initialize_lean_runtime()) {
            publish_execution_error("LeanError", "Failed to initialize Lean runtime", {});
            cb(xeus::create_error_reply("Failed to initialize Lean runtime", "LeanError", nl::json::array()));
            return;
        }
    }

    // Call the Lean REPL
    std::string result_json = call_lean_repl(code, m_current_env);

    // Parse the result
    try {
        auto result = nl::json::parse(result_json);

        if (result.contains("error")) {
            std::string error_msg = result["error"].get<std::string>();
            publish_execution_error("LeanError", error_msg, {error_msg});
            cb(xeus::create_error_reply(error_msg, "LeanError", nl::json::array()));
            return;
        }

        // Update environment
        if (result.contains("env")) {
            m_current_env = result["env"].get<int>();
        }

        // Format output
        nl::json pub_data;
        if (result.contains("messages")) {
            auto& messages = result["messages"];
            bool has_errors = false;
            std::string info_output;

            for (auto& msg : messages) {
                std::string severity = msg.value("severity", "info");
                if (severity == "error" || severity == "warning") {
                    has_errors = true;
                }
                if (severity == "info") {
                    if (!info_output.empty()) info_output += "\n";
                    info_output += msg.value("data", "");
                }
            }

            if (has_errors) {
                pub_data["text/plain"] = result_json;
            } else if (!info_output.empty()) {
                pub_data["text/plain"] = info_output;
            }
        }

        if (!pub_data.empty()) {
            publish_execution_result(execution_counter, std::move(pub_data), nl::json::object());
        }

        cb(xeus::create_successful_reply());

    } catch (const nl::json::parse_error&) {
        // Not JSON, treat as plain text output
        if (!result_json.empty()) {
            nl::json pub_data;
            pub_data["text/plain"] = result_json;
            publish_execution_result(execution_counter, std::move(pub_data), nl::json::object());
        }
        cb(xeus::create_successful_reply());
    }
}

nl::json interpreter::complete_request_impl(const std::string& /*code*/,
                                             int /*cursor_pos*/)
{
    std::cerr << "[WASM] complete_request_impl: ENTER" << std::endl;
    return xeus::create_complete_reply({}, 0, 0);
}

nl::json interpreter::inspect_request_impl(const std::string& /*code*/,
                                            int /*cursor_pos*/,
                                            int /*detail_level*/)
{
    std::cerr << "[WASM] inspect_request_impl: ENTER" << std::endl;
    return xeus::create_inspect_reply(false);
}

nl::json interpreter::is_complete_request_impl(const std::string& /*code*/)
{
    std::cerr << "[WASM] is_complete_request_impl: ENTER" << std::endl;
    return xeus::create_is_complete_reply("complete");
}

nl::json interpreter::kernel_info_request_impl()
{
    std::cerr << "[WASM] kernel_info_request_impl: ENTER" << std::endl;
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
        "Lean 4 Jupyter Kernel (WASM)"
    );
}

void interpreter::shutdown_request_impl()
{
    std::cerr << "[WASM] shutdown_request_impl: ENTER" << std::endl;
    if (m_repl_state) {
        lean_dec(static_cast<lean_object*>(m_repl_state));
        m_repl_state = nullptr;
    }
    m_initialized = false;
}

}  // namespace xeus_lean
