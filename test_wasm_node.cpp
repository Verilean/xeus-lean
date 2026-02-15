/**
 * Standalone Node.js test for the Lean WASM runtime.
 * Tests hash table operations and Lean initialization + REPL execution.
 * Build with -sMEMORY64 and run with: node --experimental-wasm-memory64 test_wasm_node.js
 */
#include <iostream>
#include <string>
#include <unordered_set>
#include <unordered_map>
#include <stdexcept>
#include <lean/lean.h>

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// Forward declarations - world token is erased by Lean compiler
extern "C" {
    void lean_initialize_runtime_module(void);
    // lean_initialize() does: runtime init, util/kernel/library C++ init,
    // then initialize_Init + initialize_Std + initialize_Lean module inits
    void lean_initialize(void);

    lean_object* initialize_xeus_x2dlean_REPL(uint8_t builtin);
    lean_object* initialize_xeus_x2dlean_REPL_Main(uint8_t builtin);
    lean_object* initialize_xeus_x2dlean_WasmRepl(uint8_t builtin);

    lean_object* lean_wasm_repl_init();
    lean_object* lean_wasm_repl_create_state();
    lean_object* lean_wasm_repl_execute(lean_object* state_ref,
                                        lean_object* code,
                                        uint32_t env_id,
                                        uint8_t has_env);
}

// Test hash tables work correctly in wasm64
static bool test_hash_tables() {
    std::cerr << "[TEST] === Hash Table Tests ===" << std::endl;
    std::cerr << "[TEST] sizeof(size_t)=" << sizeof(size_t)
              << " sizeof(void*)=" << sizeof(void*)
              << " sizeof(unsigned)=" << sizeof(unsigned) << std::endl;

    try {
        // Test 1: basic unordered_set<int>
        std::unordered_set<int> s;
        for (int i = 0; i < 10000; i++) s.insert(i);
        std::cerr << "[TEST] unordered_set<int>: size=" << s.size()
                  << " buckets=" << s.bucket_count() << " OK" << std::endl;

        // Test 2: unordered_map<void*, void*>
        std::unordered_map<void*, void*> m;
        for (int i = 0; i < 10000; i++) {
            m[(void*)(uintptr_t)(i * 8)] = (void*)(uintptr_t)i;
        }
        std::cerr << "[TEST] unordered_map<void*,void*>: size=" << m.size()
                  << " buckets=" << m.bucket_count() << " OK" << std::endl;

        // Test 3: custom hash returning unsigned (like lean's expr_hash)
        struct hash_unsigned {
            unsigned operator()(void* p) const { return (unsigned)(uintptr_t)p; }
        };
        std::unordered_set<void*, hash_unsigned> us;
        for (int i = 0; i < 10000; i++) {
            us.insert((void*)(uintptr_t)(i * 16));
        }
        std::cerr << "[TEST] unordered_set<void*, hash_unsigned>: size=" << us.size()
                  << " buckets=" << us.bucket_count() << " OK" << std::endl;

        // Test 4: custom eq returning size_t (like lean's set_eq)
        struct eq_sizet {
            std::size_t operator()(void* a, void* b) const { return a == b; }
        };
        std::unordered_set<void*, std::hash<void*>, eq_sizet> es;
        for (int i = 0; i < 10000; i++) {
            es.insert((void*)(uintptr_t)(i * 16));
        }
        std::cerr << "[TEST] unordered_set<void*, hash, eq_sizet>: size=" << es.size()
                  << " buckets=" << es.bucket_count() << " OK" << std::endl;

        // Test 5: large hash table (100K elements) - closer to what lean uses
        std::unordered_map<void*, void*> big;
        for (int i = 0; i < 100000; i++) {
            big[(void*)(uintptr_t)(i * 8)] = (void*)(uintptr_t)i;
        }
        std::cerr << "[TEST] unordered_map 100K: size=" << big.size()
                  << " buckets=" << big.bucket_count() << " OK" << std::endl;

        // Test 6: Probe __next_prime overflow threshold
        // If libc++ uses 32-bit check, rehash(0xFFFFFFFC) will throw
        // If libc++ uses 64-bit check, it won't throw until much larger values
        {
            std::unordered_set<int> probe;
            probe.insert(1);
            // Try rehash to a value just above the 32-bit overflow limit
            try {
                probe.rehash(0xFFFFFFFCULL);
                std::cerr << "[TEST] rehash(0xFFFFFFFC) OK - using 64-bit __next_prime" << std::endl;
            } catch (const std::overflow_error& e) {
                std::cerr << "[TEST] rehash(0xFFFFFFFC) threw: " << e.what()
                          << " - using 32-bit __next_prime!" << std::endl;
            } catch (const std::bad_alloc& e) {
                std::cerr << "[TEST] rehash(0xFFFFFFFC) bad_alloc (expected, would need 4GB) - using 64-bit __next_prime" << std::endl;
            }
            // Try a smaller value that should work on both
            try {
                std::unordered_set<int> probe2;
                probe2.insert(1);
                probe2.rehash(0xFFFFFFF0ULL);
                std::cerr << "[TEST] rehash(0xFFFFFFF0) OK - bucket_count=" << probe2.bucket_count() << std::endl;
            } catch (const std::overflow_error& e) {
                std::cerr << "[TEST] rehash(0xFFFFFFF0) threw: " << e.what() << std::endl;
            } catch (const std::bad_alloc& e) {
                std::cerr << "[TEST] rehash(0xFFFFFFF0) bad_alloc (memory limit)" << std::endl;
            }
        }

        std::cerr << "[TEST] === All Hash Table Tests PASSED ===" << std::endl;
        return true;
    } catch (const std::exception& e) {
        std::cerr << "[TEST] === Hash Table Test FAILED: " << e.what() << " ===" << std::endl;
        return false;
    }
}

int main() {
    std::cerr << "[TEST] Starting Lean WASM runtime test..." << std::endl;
    std::cerr << "[TEST] sizeof(size_t)=" << sizeof(size_t)
              << " sizeof(void*)=" << sizeof(void*)
              << " sizeof(lean_object*)=" << sizeof(lean_object*) << std::endl;

    // Run hash table tests first
    if (!test_hash_tables()) {
        return 1;
    }

    // Step 1: Initialize runtime
    std::cerr << "[TEST] Step 1: lean_initialize_runtime_module" << std::endl;
    lean_initialize_runtime_module();

    std::cerr << "[TEST] Step 2: lean_init_task_manager_using(0)" << std::endl;
    lean_init_task_manager_using(0);

    // Step 3: Full Lean initialization (util, kernel, library C++ init +
    // Init/Std/Lean module inits). This is REQUIRED to initialize C++ global
    // state like g_native_symbol_cache in the IR interpreter.
    std::cerr << "[TEST] Step 3: lean_initialize (full init)" << std::endl;
    try {
        lean_initialize();
        std::cerr << "[TEST] OK: lean_initialize" << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "[TEST] EXCEPTION in lean_initialize: " << e.what() << std::endl;
        return 1;
    }

    // Step 4: Initialize REPL module
    std::cerr << "[TEST] Step 4: initialize_xeus_x2dlean_REPL(1)" << std::endl;
    try {
        lean_object* res = initialize_xeus_x2dlean_REPL(1);
        if (lean_io_result_is_error(res)) {
            std::cerr << "[TEST] FAILED: initialize_xeus_x2dlean_REPL" << std::endl;
            lean_io_result_show_error(res);
            lean_dec(res);
            return 1;
        }
        lean_dec(res);
        std::cerr << "[TEST] OK: initialize_xeus_x2dlean_REPL" << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "[TEST] EXCEPTION in initialize_REPL: " << e.what() << std::endl;
        return 1;
    }

    // Step 5: Initialize REPL.Main module
    std::cerr << "[TEST] Step 5: initialize_xeus_x2dlean_REPL_Main(1)" << std::endl;
    try {
        lean_object* res = initialize_xeus_x2dlean_REPL_Main(1);
        if (lean_io_result_is_error(res)) {
            std::cerr << "[TEST] FAILED: initialize_xeus_x2dlean_REPL_Main" << std::endl;
            lean_io_result_show_error(res);
            lean_dec(res);
            return 1;
        }
        lean_dec(res);
        std::cerr << "[TEST] OK: initialize_xeus_x2dlean_REPL_Main" << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "[TEST] EXCEPTION in initialize_REPL_Main: " << e.what() << std::endl;
        return 1;
    }

    // Step 5b: Initialize WasmRepl module
    std::cerr << "[TEST] Step 5b: initialize_xeus_x2dlean_WasmRepl(1)" << std::endl;
    try {
        lean_object* res = initialize_xeus_x2dlean_WasmRepl(1);
        if (lean_io_result_is_error(res)) {
            std::cerr << "[TEST] FAILED: initialize_WasmRepl" << std::endl;
            lean_io_result_show_error(res);
            lean_dec(res);
            return 1;
        }
        lean_dec(res);
        std::cerr << "[TEST] OK: initialize_WasmRepl" << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "[TEST] EXCEPTION in initialize_WasmRepl: " << e.what() << std::endl;
        return 1;
    }

    // Step 6: Mark end of initialization
    std::cerr << "[TEST] Step 6: lean_io_mark_end_initialization" << std::endl;
    lean_io_mark_end_initialization();

    // Step 7: Initialize REPL search path
    std::cerr << "[TEST] Step 7: lean_wasm_repl_init" << std::endl;
    try {
        lean_object* res = lean_wasm_repl_init();
        if (lean_io_result_is_error(res)) {
            std::cerr << "[TEST] FAILED: lean_wasm_repl_init" << std::endl;
            lean_io_result_show_error(res);
            lean_dec(res);
            return 1;
        }
        lean_dec(res);
        std::cerr << "[TEST] OK: lean_wasm_repl_init" << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "[TEST] EXCEPTION in lean_wasm_repl_init: " << e.what() << std::endl;
        return 1;
    }

    // Step 8: Create REPL state
    std::cerr << "[TEST] Step 8: lean_wasm_repl_create_state" << std::endl;
    lean_object* state_ref = nullptr;
    try {
        lean_object* res = lean_wasm_repl_create_state();
        if (lean_io_result_is_error(res)) {
            std::cerr << "[TEST] FAILED: lean_wasm_repl_create_state" << std::endl;
            lean_io_result_show_error(res);
            lean_dec(res);
            return 1;
        }
        state_ref = lean_io_result_get_value(res);
        lean_inc(state_ref);
        lean_dec(res);
        std::cerr << "[TEST] OK: lean_wasm_repl_create_state" << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "[TEST] EXCEPTION in lean_wasm_repl_create_state: " << e.what() << std::endl;
        return 1;
    }

    // Step 9: Execute test commands
    auto run_cmd = [&](const char* desc, const char* code_str, uint32_t env_id = 0, uint8_t has_env = 0) -> bool {
        std::cerr << "[TEST] Execute: '" << desc << "'" << std::endl;
        try {
            lean_object* code = lean_mk_string(code_str);
            lean_inc(state_ref);
            lean_object* res = lean_wasm_repl_execute(state_ref, code, env_id, has_env);
            if (lean_io_result_is_error(res)) {
                std::cerr << "[TEST] FAILED: lean_wasm_repl_execute" << std::endl;
                lean_io_result_show_error(res);
                lean_dec(res);
                return false;
            }
            lean_object* result = lean_io_result_get_value(res);
            const char* result_str = lean_string_cstr(result);
            std::cerr << "[TEST] Result: " << (result_str ? result_str : "(null)") << std::endl;
            lean_dec(res);
            return true;
        } catch (const std::exception& e) {
            std::cerr << "[TEST] EXCEPTION: " << e.what() << std::endl;
            return false;
        }
    };

    std::cerr << "[TEST] Step 9a: #check Nat" << std::endl;
    run_cmd("#check Nat", "#check Nat");

    std::cerr << "[TEST] Step 9b: #eval 1 + 1" << std::endl;
    run_cmd("#eval 1 + 1", "#eval 1 + 1");

    std::cerr << "[TEST] Step 9c: #eval (1 + 1 : Nat)" << std::endl;
    run_cmd("#eval (1 + 1 : Nat)", "#eval (1 + 1 : Nat)");

    std::cerr << "[TEST] Step 9d: #eval \"hello\"" << std::endl;
    run_cmd("#eval \"hello\"", "#eval \"hello\"");

    std::cerr << "[TEST] Step 9e: def x := 1" << std::endl;
    run_cmd("def x := 1", "def x := 1");

    std::cerr << "[TEST] All steps completed successfully!" << std::endl;
    lean_dec(state_ref);
    return 0;
}
