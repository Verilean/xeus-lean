#############################################################################
# Copyright (c) 2025, xeus-lean contributors
#
# Distributed under the terms of the Apache Software License 2.0.
#
# The full license is in the file LICENSE, distributed with this software.
#############################################################################

# LeanStage0Wasm.cmake - Build Lean4 stage0 stdlib and REPL as WASM static libs
#
# Requires LeanRtWasm.cmake to have been included first (it populates the
# lean4 FetchContent and sets up the stub uv.h directory).
#
# Usage:
#   include(LeanStage0Wasm)
#   build_lean_stage0_wasm(INIT_LIB STD_LIB LEAN_LIB REPL_LIB)

set(_STAGE0_MODULE_DIR "${CMAKE_CURRENT_LIST_DIR}")

function(build_lean_stage0_wasm out_init out_std out_lean out_repl)
    # lean4 FetchContent must already be populated by LeanRtWasm
    FetchContent_GetProperties(lean4)
    if(NOT lean4_POPULATED)
        message(FATAL_ERROR "lean4 FetchContent not populated. Include LeanRtWasm and call fetch_and_build_leanrt() first.")
    endif()

    set(LEAN4_SRC_DIR "${lean4_SOURCE_DIR}")
    set(LEAN4_INCLUDE "${LEAN4_SRC_DIR}/src/include")
    set(LEAN4_UV_STUBS_DIR "${_STAGE0_MODULE_DIR}/stubs")
    set(STAGE0_DIR "${LEAN4_SRC_DIR}/stage0/stdlib")

    message(STATUS "Building Lean stage0 WASM libraries from: ${STAGE0_DIR}")

    # Common compile definitions for all stage0 C files
    set(STAGE0_COMPILE_DEFS LEAN_EXPORTING LEAN_EMSCRIPTEN NDEBUG)

    # Common include directories
    set(STAGE0_INCLUDE_DIRS
        ${LEAN4_UV_STUBS_DIR}
        ${LEAN4_INCLUDE}
        ${LEAN4_SRC_DIR}/src
    )

    # Common compile flags
    set(STAGE0_COMPILE_FLAGS
        -fPIC
        -O2
        -g2
        -Wno-unused-parameter
        -Wno-unused-label
        -Wno-unused-but-set-variable
        -Wno-deprecated
        -Wno-sign-compare
        -Wno-missing-field-initializers
    )

    # ---- Init library ----
    file(GLOB_RECURSE INIT_SOURCES "${STAGE0_DIR}/Init/*.c")
    list(APPEND INIT_SOURCES "${STAGE0_DIR}/Init.c")
    list(LENGTH INIT_SOURCES _init_count)
    message(STATUS "  Init: ${_init_count} source files")

    add_library(lean_stage0_init STATIC ${INIT_SOURCES})
    target_include_directories(lean_stage0_init PRIVATE ${STAGE0_INCLUDE_DIRS})
    target_compile_definitions(lean_stage0_init PRIVATE ${STAGE0_COMPILE_DEFS})
    target_compile_options(lean_stage0_init PRIVATE ${STAGE0_COMPILE_FLAGS})

    # ---- Std library ----
    file(GLOB_RECURSE STD_SOURCES "${STAGE0_DIR}/Std/*.c")
    list(APPEND STD_SOURCES "${STAGE0_DIR}/Std.c")
    list(LENGTH STD_SOURCES _std_count)
    message(STATUS "  Std: ${_std_count} source files")

    add_library(lean_stage0_std STATIC ${STD_SOURCES})
    target_include_directories(lean_stage0_std PRIVATE ${STAGE0_INCLUDE_DIRS})
    target_compile_definitions(lean_stage0_std PRIVATE ${STAGE0_COMPILE_DEFS})
    target_compile_options(lean_stage0_std PRIVATE ${STAGE0_COMPILE_FLAGS})

    # ---- Lean library ----
    file(GLOB_RECURSE LEAN_SOURCES "${STAGE0_DIR}/Lean/*.c")
    list(APPEND LEAN_SOURCES "${STAGE0_DIR}/Lean.c")
    list(LENGTH LEAN_SOURCES _lean_count)
    message(STATUS "  Lean: ${_lean_count} source files")

    add_library(lean_stage0_lean STATIC ${LEAN_SOURCES})
    target_include_directories(lean_stage0_lean PRIVATE ${STAGE0_INCLUDE_DIRS})
    target_compile_definitions(lean_stage0_lean PRIVATE ${STAGE0_COMPILE_DEFS})
    target_compile_options(lean_stage0_lean PRIVATE ${STAGE0_COMPILE_FLAGS})

    # ---- REPL library (from project .lake/build/ir/) ----
    set(REPL_IR_DIR "${CMAKE_SOURCE_DIR}/.lake/build/ir")
    file(GLOB_RECURSE REPL_SOURCES "${REPL_IR_DIR}/REPL/*.c")
    list(APPEND REPL_SOURCES "${REPL_IR_DIR}/REPL.c")
    list(APPEND REPL_SOURCES "${REPL_IR_DIR}/WasmRepl.c")

    # NOTE: XeusKernel.c is NOT included — it defines the native kernel's main()
    # which conflicts with the WASM entry point (xinterpreter_wasm.cpp).

    list(LENGTH REPL_SOURCES _repl_count)
    message(STATUS "  REPL: ${_repl_count} source files from ${REPL_IR_DIR}")

    add_library(lean_stage0_repl STATIC ${REPL_SOURCES})
    target_include_directories(lean_stage0_repl PRIVATE ${STAGE0_INCLUDE_DIRS})
    target_compile_definitions(lean_stage0_repl PRIVATE ${STAGE0_COMPILE_DEFS})
    target_compile_options(lean_stage0_repl PRIVATE ${STAGE0_COMPILE_FLAGS})

    # Return target names
    set(${out_init} lean_stage0_init PARENT_SCOPE)
    set(${out_std} lean_stage0_std PARENT_SCOPE)
    set(${out_lean} lean_stage0_lean PARENT_SCOPE)
    set(${out_repl} lean_stage0_repl PARENT_SCOPE)

    message(STATUS "Lean stage0 WASM libraries configured")
endfunction()
