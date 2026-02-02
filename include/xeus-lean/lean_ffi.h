/***************************************************************************
* Copyright (c) 2025, xeus-lean contributors
*
* Distributed under the terms of the Apache Software License 2.0.
*
* The full license is in the file LICENSE, distributed with this software.
****************************************************************************/

#ifndef LEAN_FFI_H
#define LEAN_FFI_H

#include <lean/lean.h>

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the Lean runtime (must be called once)
void lean_initialize_runtime_module();

// Initialize the REPL
lean_obj_res lean_repl_init(lean_obj_arg unit);

// Execute a command (takes handle and JSON string, returns JSON string)
lean_obj_res lean_repl_execute_cmd(lean_obj_arg handle, lean_obj_arg cmd_json, lean_obj_arg world);

// Free the REPL handle
lean_obj_res lean_repl_free(lean_obj_arg handle, lean_obj_arg world);

#ifdef __cplusplus
}
#endif

#endif // LEAN_FFI_H
