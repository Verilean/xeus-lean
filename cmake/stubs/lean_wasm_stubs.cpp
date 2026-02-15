/*
 * Stub implementations for Lean4 functions not available in WASM.
 *
 * The WASM build now compiles kernel/, library/, util/, and initialize/
 * C++ source files directly. This stubs file only needs to cover:
 * - xeus native FFI functions (replaced by xinterpreter_wasm.cpp in WASM)
 *
 * NOTE: Stage0 C code erases IO world tokens, so these stubs must match
 * the stage0 calling convention (fewer args than the Lean type suggests).
 */

#include <lean/lean.h>
#include <cstdio>
#include <cstdlib>
#include <string>

static lean_obj_res lean_wasm_stub_error(const char* name) {
    lean_object* msg = lean_mk_string((std::string("WASM stub: ") + name + " is not available").c_str());
    return lean_io_result_mk_error(lean_mk_io_user_error(msg));
}

extern "C" {

// =============================================================================
// xeus native FFI stubs (WASM build uses xinterpreter_wasm instead)
// Signatures match stage0 calling convention (IO world token erased).
// =============================================================================

LEAN_EXPORT lean_obj_res xeus_ffi_initialize() {
    // No-op in WASM: kernel initialization is handled by xinterpreter_wasm.cpp
    return lean_io_result_mk_ok(lean_box(0));
}

// IO (Option KernelHandle) → return none (not used in WASM)
LEAN_EXPORT lean_obj_res xeus_kernel_init(lean_obj_arg connection_file) {
    lean_dec_ref(connection_file);
    return lean_io_result_mk_ok(lean_box(0));  // Option.none
}

// IO String → return empty string
LEAN_EXPORT lean_obj_res xeus_kernel_poll(lean_obj_arg handle, uint32_t timeout_ms) {
    return lean_io_result_mk_ok(lean_mk_string(""));
}

// IO Unit → no-op
LEAN_EXPORT lean_obj_res xeus_kernel_send_result(lean_obj_arg handle, uint32_t exec_count,
                                                  lean_obj_arg data) {
    lean_dec_ref(data);
    return lean_io_result_mk_ok(lean_box(0));
}

// IO Unit → no-op
LEAN_EXPORT lean_obj_res xeus_kernel_send_error(lean_obj_arg handle, uint32_t exec_count,
                                                 lean_obj_arg error) {
    lean_dec_ref(error);
    return lean_io_result_mk_ok(lean_box(0));
}

// IO Bool → return true (stop immediately if loop ever runs)
LEAN_EXPORT lean_obj_res xeus_kernel_should_stop(lean_obj_arg handle) {
    return lean_io_result_mk_ok(lean_box(1));  // Bool.true
}

} // extern "C"
