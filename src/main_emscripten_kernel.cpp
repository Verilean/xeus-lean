/***************************************************************************
* Copyright (c) 2025, xeus-lean contributors
*
* Distributed under the terms of the Apache Software License 2.0.
*
* The full license is in the file LICENSE, distributed with this software.
****************************************************************************/

#include <iostream>
#include <memory>

#include <emscripten/bind.h>

#include "xeus-lean/xinterpreter_wasm.hpp"
#include "xeus-lite/xembind.hpp"

EMSCRIPTEN_BINDINGS(my_module) {
    xeus::export_core();
    using interpreter_type = xeus_lean::interpreter;
    xeus::export_kernel<interpreter_type>("xkernel");
}
