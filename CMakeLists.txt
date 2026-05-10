############################################################################
# Copyright (c) 2025, xeus-lean contributors
#
# Distributed under the terms of the Apache Software License 2.0.
#
# The full license is in the file LICENSE, distributed with this software.
############################################################################

cmake_minimum_required(VERSION 3.10.0)
project(xeus-lean VERSION 0.1.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake;${CMAKE_MODULE_PATH}")

set(XEUS_LEAN_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)

include(GNUInstallDirs)

# ============================================================================
# EMSCRIPTEN (WASM) BUILD
# ============================================================================

if(EMSCRIPTEN)
    message(STATUS "Building xeus-lean for WASM (emscripten)")
    add_compile_definitions(XEUS_LEAN_EMSCRIPTEN_WASM_BUILD)

    # Clear macOS linker flags that leak from nix and break wasm-ld,
    # then set Memory64 flags. Use CMAKE_*_FLAGS (not add_compile_options)
    # so flags propagate to all FetchContent subdirectories (xeus, xeus-lite, etc.).
    # Lean's compacted region / .olean format is pointer-size dependent.
    set(CMAKE_C_FLAGS "-sMEMORY64")
    set(CMAKE_CXX_FLAGS "-sMEMORY64 -fwasm-exceptions")
    set(CMAKE_EXE_LINKER_FLAGS "-sMEMORY64")
    set(CMAKE_SHARED_LINKER_FLAGS "-sMEMORY64")
    set(CMAKE_MODULE_LINKER_FLAGS "-sMEMORY64")

    # Dependencies (built from source for Memory64/wasm64 compatibility)
    # ===================================================================

    include(FetchContent)
    # Allow FetchContent_Populate (needed to patch sources before add_subdirectory)
    cmake_policy(SET CMP0169 OLD)

    # nlohmann_json (header-only, no recompilation needed)
    find_package(nlohmann_json QUIET)
    if(NOT nlohmann_json_FOUND)
        FetchContent_Declare(nlohmann_json
            GIT_REPOSITORY https://github.com/nlohmann/json.git
            GIT_TAG v3.12.0
            EXCLUDE_FROM_ALL)
        set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
        set(JSON_Install OFF CACHE BOOL "" FORCE)
        FetchContent_MakeAvailable(nlohmann_json)
    endif()

    # xtl (header-only, required by xeus)
    FetchContent_Declare(xtl
        GIT_REPOSITORY https://github.com/xtensor-stack/xtl.git
        GIT_TAG 0.7.7)
    FetchContent_MakeAvailable(xtl)

    # xeus (must be compiled from source for wasm64)
    set(XEUS_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    set(XEUS_STATIC_DEPENDENCIES ON CACHE BOOL "" FORCE)
    set(XEUS_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(xeus
        GIT_REPOSITORY https://github.com/jupyter-xeus/xeus.git
        GIT_TAG 5.2.6)
    # Use Populate + patch + add_subdirectory instead of MakeAvailable
    # to fix export(EXPORT)/install(EXPORT) failures in FetchContent builds
    # (nlohmann_json built with EXCLUDE_FROM_ALL is not in any export set)
    FetchContent_GetProperties(xeus)
    if(NOT xeus_POPULATED)
        FetchContent_Populate(xeus)
        file(READ "${xeus_SOURCE_DIR}/CMakeLists.txt" _xeus_cml)
        string(REGEX REPLACE "export\\(EXPORT [^)]+\\)" "# export(EXPORT) disabled for FetchContent" _xeus_cml "${_xeus_cml}")
        string(REGEX REPLACE "install\\(EXPORT [^)]+\\)" "# install(EXPORT) disabled for FetchContent" _xeus_cml "${_xeus_cml}")
        # Fix: add EMSCRIPTEN guard for -lutil -lrt (not available in wasm)
        string(REPLACE "UNIX AND NOT APPLE)" "UNIX AND NOT APPLE AND NOT EMSCRIPTEN)" _xeus_cml "${_xeus_cml}")
        file(WRITE "${xeus_SOURCE_DIR}/CMakeLists.txt" "${_xeus_cml}")
        add_subdirectory(${xeus_SOURCE_DIR} ${xeus_BINARY_DIR} EXCLUDE_FROM_ALL)
    endif()

    # Add xeus cmake modules to path (WasmBuildOptions.cmake needed by xeus-lite)
    list(APPEND CMAKE_MODULE_PATH "${CMAKE_BINARY_DIR}/_deps/xeus-src/cmake")

    # xeus-lite (must be compiled from source for wasm64)
    # Create shim config so xeus-lite's find_package(xeus 5.0.0) succeeds
    # (xeus targets are already available from FetchContent above)
    file(WRITE "${CMAKE_BINARY_DIR}/xeus-shim/xeusConfig.cmake"
        "set(xeus_FOUND TRUE)\nset(xeus_VERSION \"5.2.6\")\n")
    file(WRITE "${CMAKE_BINARY_DIR}/xeus-shim/xeusConfigVersion.cmake"
        "set(PACKAGE_VERSION \"5.2.6\")\nset(PACKAGE_VERSION_COMPATIBLE TRUE)\nset(PACKAGE_VERSION_EXACT FALSE)\n")
    set(xeus_DIR "${CMAKE_BINARY_DIR}/xeus-shim" CACHE PATH "" FORCE)

    set(XEUS_LITE_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    set(XEUS_LITE_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(xeus-lite
        GIT_REPOSITORY https://github.com/jupyter-xeus/xeus-lite.git
        GIT_TAG 3.2.1)
    # Same FetchContent export fix as xeus above
    FetchContent_GetProperties(xeus-lite)
    if(NOT xeus-lite_POPULATED)
        FetchContent_Populate(xeus-lite)
        file(READ "${xeus-lite_SOURCE_DIR}/CMakeLists.txt" _xlite_cml)
        string(REGEX REPLACE "export\\(EXPORT [^)]+\\)" "# export(EXPORT) disabled for FetchContent" _xlite_cml "${_xlite_cml}")
        string(REGEX REPLACE "install\\(EXPORT [^)]+\\)" "# install(EXPORT) disabled for FetchContent" _xlite_cml "${_xlite_cml}")
        file(WRITE "${xeus-lite_SOURCE_DIR}/CMakeLists.txt" "${_xlite_cml}")
        add_subdirectory(${xeus-lite_SOURCE_DIR} ${xeus-lite_BINARY_DIR} EXCLUDE_FROM_ALL)
    endif()

    # Build libleanrt from lean4 source
    # ==================================

    include(LeanRtWasm)
    fetch_and_build_leanrt(LEANRT_LIB LEAN4_INCLUDE_DIR)

    # Build Lean stage0 stdlib + REPL as WASM static libs
    # ====================================================

    include(LeanStage0Wasm)
    build_lean_stage0_wasm(STAGE0_INIT_LIB STAGE0_STD_LIB STAGE0_LEAN_LIB STAGE0_REPL_LIB)

    # xeus-lean WASM static library
    # ==============================

    add_library(xeus-lean-static STATIC src/xinterpreter_wasm.cpp)

    target_include_directories(xeus-lean-static PUBLIC
        $<BUILD_INTERFACE:${XEUS_LEAN_INCLUDE_DIR}>
        $<INSTALL_INTERFACE:include>
    )

    target_link_libraries(xeus-lean-static
        PUBLIC xeus-static
        PUBLIC nlohmann_json::nlohmann_json
        PUBLIC ${LEANRT_LIB}
    )

    target_compile_features(xeus-lean-static PRIVATE cxx_std_17)

    if(EMSCRIPTEN)
        target_compile_options(xeus-lean-static PRIVATE -fPIC -g2)
    endif()

    # xlean WASM executable
    # ======================

    # Sparkle C FFI implementations + Lean-compiled IR sources.
    # Needed for Signal.sample / Signal.circuit in the WASM REPL.
    # The Lean interpreter looks up `@[extern]` decls by their mangled
    # `lp_sparkle___private_...___boxed` name, which lives in the .c
    # files Lean generated under .lake/build/ir/. We copy all sources
    # to the build dir with a .cpp extension so CMake's C++17 flag
    # doesn't reject a .c file. To prevent wasm-ld DCE from stripping
    # these symbols (nothing in main references them; the interpreter
    # resolves them dynamically), we wrap them in a static archive
    # and link with --whole-archive.
    set(SPARKLE_ROOT "${CMAKE_SOURCE_DIR}/examples/sparkle/.lake/packages/sparkle")
    set(SPARKLE_C_BARRIER "${SPARKLE_ROOT}/c_src/sparkle_barrier.c")
    set(SPARKLE_IR_DIR "${SPARKLE_ROOT}/.lake/build/ir")
    set(SPARKLE_WASM_SOURCES)
    if(EXISTS "${SPARKLE_C_BARRIER}")
        # Wrap in extern "C" so the C++ compiler does not name-mangle
        # sparkle_cache_get / sparkle_eval_at. The callers (Signal.c)
        # reference them as plain C symbols.
        file(READ "${SPARKLE_C_BARRIER}" _barrier_body)
        # #include must stay outside extern "C" (lean.h pulls in C++
        # headers that must have C++ linkage). Strip the original
        # #include lines and emit them before the extern "C" block.
        string(REGEX MATCHALL "#include[^\n]*\n" _barrier_includes "${_barrier_body}")
        string(REGEX REPLACE "#include[^\n]*\n" "" _barrier_body_no_inc "${_barrier_body}")
        string(JOIN "" _barrier_inc_str ${_barrier_includes})
        # WASM debug: rename the upstream functions to *_impl so we can
        # wrap them with call-counter logging that prints to stderr.
        # Useful for diagnosing simulation hangs in the WASM REPL.
        string(REPLACE "sparkle_cache_get" "sparkle_cache_get_impl" _barrier_body_no_inc "${_barrier_body_no_inc}")
        string(REPLACE "sparkle_eval_at" "sparkle_eval_at_impl" _barrier_body_no_inc "${_barrier_body_no_inc}")
        set(SPARKLE_C_CPP "${CMAKE_BINARY_DIR}/sparkle_barrier.cpp")
        file(WRITE "${SPARKLE_C_CPP}"
"${_barrier_inc_str}
#include <cstdio>
extern \"C\" {
${_barrier_body_no_inc}

// Wrappers that print every Nth call to stderr — surfaces in the
// browser console as `[sparkle_eval_at] call #...`.
LEAN_EXPORT lean_obj_res sparkle_cache_get(b_lean_obj_arg ref, b_lean_obj_arg t_obj, lean_obj_arg fallback) {
    static unsigned long n = 0;
    if ((++n & 0xFFF) == 1) std::fprintf(stderr, \"[sparkle_cache_get] call #%lu\\n\", n);
    return sparkle_cache_get_impl(ref, t_obj, fallback);
}
LEAN_EXPORT lean_obj_res sparkle_eval_at(b_lean_obj_arg signal_val, b_lean_obj_arg t, lean_obj_arg world) {
    static unsigned long n = 0;
    if ((++n & 0x3F) == 1) std::fprintf(stderr, \"[sparkle_eval_at] call #%lu (t=%lu)\\n\", n, lean_unbox(t));
    return sparkle_eval_at_impl(signal_val, t, world);
}
}
")
        list(APPEND SPARKLE_WASM_SOURCES "${SPARKLE_C_CPP}")
        message(STATUS "Including sparkle_barrier.cpp + diagnostic wrappers in xlean for WASM FFI")
    endif()
    set(_excluded_init_syms "")
    if(EXISTS "${SPARKLE_IR_DIR}")
        file(GLOB_RECURSE _SPARKLE_IR_C RELATIVE "${SPARKLE_IR_DIR}"
             "${SPARKLE_IR_DIR}/*.c")
        # Exclude every IR file that references sparkle_jit_* — those
        # symbols live in sparkle_jit.c which has mismatched signatures
        # vs the IR's view. Stubs for their `initialize_sparkle_*`
        # entry points are provided below.
        set(_filtered "")
        foreach(_rel ${_SPARKLE_IR_C})
            file(STRINGS "${SPARKLE_IR_DIR}/${_rel}" _jit_refs REGEX "sparkle_jit_")
            if(_jit_refs)
                # Derive the module name from path so we can stub init.
                string(REGEX REPLACE "\\.c$" "" _mod "${_rel}")
                string(REPLACE "/" "_" _mod "${_mod}")
                list(APPEND _excluded_init_syms "${_mod}")
            else()
                list(APPEND _filtered "${_rel}")
            endif()
        endforeach()
        set(_SPARKLE_IR_C ${_filtered})
        foreach(_rel ${_SPARKLE_IR_C})
            string(REPLACE "/" "_" _flat "${_rel}")
            string(REGEX REPLACE "\\.c$" ".cpp" _flat "${_flat}")
            set(_dst "${CMAKE_BINARY_DIR}/sparkle_ir_${_flat}")
            configure_file("${SPARKLE_IR_DIR}/${_rel}" "${_dst}" COPYONLY)
            list(APPEND SPARKLE_WASM_SOURCES "${_dst}")
        endforeach()
        list(LENGTH _SPARKLE_IR_C _n_ir)
        message(STATUS "Including ${_n_ir} Sparkle IR .cpp files in xlean for WASM FFI")
    endif()
    # Stub initialize_sparkle_* for every IR file we excluded above,
    # so Sparkle.cpp's module-init sequence still links.
    set(SPARKLE_JIT_STUB "${CMAKE_BINARY_DIR}/sparkle_jit_stubs.cpp")
    set(_init_stub_decls "")
    foreach(_mod ${_excluded_init_syms})
        set(_init_stub_decls "${_init_stub_decls}INIT_STUB(${_mod})\n")
    endforeach()
    file(WRITE "${SPARKLE_JIT_STUB}"
"#include <lean/lean.h>
extern \"C\" {
// The Lean 4.28 IR calls module init with a single uint8_t (builtin flag).
// Older Lean/sparkle_jit.c used (uint8_t, lean_object*); match the IR.
#define INIT_STUB(mod) LEAN_EXPORT lean_object* initialize_sparkle_##mod(uint8_t builtin) { return lean_io_result_mk_ok(lean_box(0)); }
${_init_stub_decls}}
")
    list(APPEND SPARKLE_WASM_SOURCES "${SPARKLE_JIT_STUB}")
    list(LENGTH _excluded_init_syms _n_stubs)
    message(STATUS "Including sparkle_jit_stubs.cpp (${_n_stubs} init stubs)")
    if(SPARKLE_WASM_SOURCES)
        add_library(sparkle_wasm STATIC ${SPARKLE_WASM_SOURCES})
        target_compile_options(sparkle_wasm PRIVATE -fPIC -g2)
        target_compile_features(sparkle_wasm PRIVATE cxx_std_17)
        target_include_directories(sparkle_wasm PRIVATE ${LEAN4_INCLUDE_DIR})
        set_property(TARGET sparkle_wasm PROPERTY POSITION_INDEPENDENT_CODE ON)
    endif()
    add_executable(xlean src/main_emscripten_kernel.cpp)
    target_link_libraries(xlean PRIVATE xeus-lite)
    target_link_libraries(xlean PRIVATE xeus-lean-static)
    # Force-link the entire Sparkle archive so wasm-ld does not strip
    # the dynamically-resolved `lp_sparkle_*` symbols.
    # --whole-archive alone is not enough: wasm-ld still gc-sections
    # unreferenced symbols. --export-dynamic + --no-gc-sections keeps
    # them in the final wasm so the Lean interpreter's dlsym() works.
    if(TARGET sparkle_wasm)
        # Extract LEAN_EXPORT symbol names from the generated IR .cpp
        # files at configure time and pass them to emcc as
        # EXPORTED_FUNCTIONS. wasm-ld LTO drops symbols nothing
        # references; the only reliable way to keep interpreter-
        # resolved symbols in the final wasm is to name them.
        set(_sparkle_syms "")
        foreach(_src ${SPARKLE_WASM_SOURCES})
            # Skip the stubs file so we don't pick up the macro
            # parameter `name` as a symbol.
            if(_src MATCHES "sparkle_jit_stubs\\.cpp$")
                continue()
            endif()
            file(STRINGS "${_src}" _hits REGEX "LEAN_EXPORT[^(]*[ *]([a-zA-Z_][a-zA-Z_0-9]*)\\(")
            foreach(_l ${_hits})
                if(_l MATCHES "LEAN_EXPORT[^(]*[ *]([a-zA-Z_][a-zA-Z_0-9]*)\\(")
                    list(APPEND _sparkle_syms "_${CMAKE_MATCH_1}")
                endif()
            endforeach()
        endforeach()
        # Always include the C FFI entry points used by Sparkle IR.
        list(APPEND _sparkle_syms "_sparkle_cache_get" "_sparkle_eval_at")
        list(REMOVE_DUPLICATES _sparkle_syms)
        list(LENGTH _sparkle_syms _n_syms)
        message(STATUS "Sparkle exports: ${_n_syms} symbols will be kept")
        list(JOIN _sparkle_syms "," _sparkle_csv)
        set(_sparkle_exports_file "${CMAKE_BINARY_DIR}/sparkle_exports.txt")
        # No _main — this executable uses EMSCRIPTEN_BINDINGS and
        # emscripten provides its own entry stub. Listing _main here
        # triggers "undefined exported symbol" since the user code
        # never defines it.
        file(WRITE "${_sparkle_exports_file}" "[${_sparkle_csv}]")
        # LINK_FLAGS does NOT evaluate generator expressions, so use
        # the concrete archive path instead of $<TARGET_FILE:...>.
        set(_sparkle_archive "${CMAKE_BINARY_DIR}/libsparkle_wasm.a")
        set_property(TARGET xlean APPEND_STRING PROPERTY LINK_FLAGS
            " -Wl,--whole-archive ${_sparkle_archive} -Wl,--no-whole-archive -sEXPORTED_FUNCTIONS=@${_sparkle_exports_file}")
        add_dependencies(xlean sparkle_wasm)
    endif()
    # Link stage0 libraries (order matters: REPL -> Lean -> Std -> Init -> leanrt)
    target_link_libraries(xlean PRIVATE
        ${STAGE0_REPL_LIB}
        ${STAGE0_LEAN_LIB}
        ${STAGE0_STD_LIB}
        ${STAGE0_INIT_LIB}
        ${LEANRT_LIB}
    )
    target_compile_options(xlean PRIVATE -fPIC -g2)

    # Compile options (replaces xeus_wasm_compile_options)
    target_compile_options(xlean
        PUBLIC --std=c++17
        PUBLIC -Wno-deprecated
        PUBLIC "SHELL: -fwasm-exceptions"
    )
    set_property(TARGET xlean PROPERTY POSITION_INDEPENDENT_CODE ON)

    # Link options - set directly instead of using xeus_wasm_link_options
    # to avoid duplicate flags and critically to REMOVE MAIN_MODULE=1.
    # MAIN_MODULE=1 (dynamic linking) prevents ALLOW_MEMORY_GROWTH and
    # MAXIMUM_MEMORY from working, causing std::bad_alloc when loading
    # Init modules. We link everything statically so it's not needed.
    target_link_options(xlean
        PUBLIC "SHELL: -lembind"
        PUBLIC -Wno-unused-command-line-argument
        PUBLIC "SHELL: -fwasm-exceptions"
        PUBLIC "SHELL: -s MODULARIZE=1"
        PUBLIC "SHELL: -s EXPORT_NAME=\"createXeusModule\""
        PUBLIC "SHELL: -s EXPORT_ES6=0"
        PUBLIC "SHELL: -s ASSERTIONS=2"
        PUBLIC "SHELL: -s ALLOW_MEMORY_GROWTH=1"
        PUBLIC "SHELL: -s EXIT_RUNTIME=1"
        PUBLIC "SHELL: -s WASM=1"
        PUBLIC "SHELL: -s ENVIRONMENT=web,worker,node"
        PUBLIC "SHELL: -s STACK_SIZE=64mb"
        PUBLIC "SHELL: -s INITIAL_MEMORY=1024mb"
        PUBLIC "SHELL: -s MAXIMUM_MEMORY=4gb"
        PUBLIC "SHELL: -s WASM_BIGINT"
        PUBLIC "SHELL: -s EXPORTED_RUNTIME_METHODS='[\"FS\",\"ENV\",\"PATH\",\"ERRNO_CODES\"]'"
        PUBLIC "SHELL: -s FORCE_FILESYSTEM"
        # EXPORT_ALL=1 did not retain Sparkle IR symbols; we use
        # --whole-archive below on sparkle_wasm instead.
    )

    target_link_options(xlean
        PUBLIC "SHELL: --pre-js ${CMAKE_CURRENT_SOURCE_DIR}/src/pre.js"
        # Order matters: fzstd defines `self.fzstd`/`globalThis.fzstd` and
        # post.js consumes it. Both files end up as separate scripts inside
        # the emscripten worker bundle and run in declaration order.
        PUBLIC "SHELL: --post-js ${CMAKE_CURRENT_SOURCE_DIR}/src/fzstd.umd.js"
        PUBLIC "SHELL: --post-js ${CMAKE_CURRENT_SOURCE_DIR}/src/post.js"
    )

    # Embed Lean .olean files for Init module
    # ========================================
    # The Lean elaborator needs .olean files to import modules (e.g. `import Init`).
    # We copy them from the host Lean toolchain to a staging directory and embed
    # them in the WASM virtual filesystem via --embed-file (data is embedded
    # directly in the JS file, avoiding fetch issues in Web Worker contexts).

    if(NOT LEAN_TOOLCHAIN_DIR)
        # Try to find lean on the host system (not cross-compiled)
        find_program(LEAN_HOST_EXECUTABLE lean
            HINTS $ENV{HOME}/.elan/bin
            NO_CMAKE_FIND_ROOT_PATH)
        if(LEAN_HOST_EXECUTABLE)
            execute_process(
                COMMAND ${LEAN_HOST_EXECUTABLE} --print-prefix
                OUTPUT_VARIABLE LEAN_TOOLCHAIN_DIR
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET)
        endif()
    endif()

    if(LEAN_TOOLCHAIN_DIR)
        set(LEAN_OLEAN_SRC "${LEAN_TOOLCHAIN_DIR}/lib/lean")
        set(LEAN_OLEAN_STAGING "${CMAKE_BINARY_DIR}/olean_staging/lib/lean")

        if(EXISTS "${LEAN_OLEAN_SRC}/Init.olean")
            message(STATUS "Lean .olean source: ${LEAN_OLEAN_SRC}")

            # Copy all Init module artifacts (top-level + recursive)
            # Lean 4.28+ splits module data into multiple parts:
            #   .olean          = exported level
            #   .olean.server   = server level
            #   .olean.private  = private level (needed for `import all`)
            #   .ir             = IR data (needed for interpretation/elaboration)
            file(MAKE_DIRECTORY "${LEAN_OLEAN_STAGING}")

            # Copy ALL Init module artifacts (olean, server, private, ir)
            # Init must be fully embedded for basic Lean to work.
            foreach(_ext olean olean.server olean.private ir)
                if(EXISTS "${LEAN_OLEAN_SRC}/Init.${_ext}")
                    file(COPY "${LEAN_OLEAN_SRC}/Init.${_ext}" DESTINATION "${LEAN_OLEAN_STAGING}/")
                endif()
            endforeach()

            # Copy all Init/**/* files preserving directory structure
            file(GLOB_RECURSE _INIT_FILES
                RELATIVE "${LEAN_OLEAN_SRC}"
                "${LEAN_OLEAN_SRC}/Init/*.olean"
                "${LEAN_OLEAN_SRC}/Init/*.olean.server"
                "${LEAN_OLEAN_SRC}/Init/*.olean.private"
                "${LEAN_OLEAN_SRC}/Init/*.ir")
            list(LENGTH _INIT_FILES _file_count)
            message(STATUS "Copying ${_file_count} Init module files to staging")
            foreach(_f ${_INIT_FILES})
                get_filename_component(_dir "${_f}" DIRECTORY)
                file(MAKE_DIRECTORY "${LEAN_OLEAN_STAGING}/${_dir}")
                file(COPY "${LEAN_OLEAN_SRC}/${_f}" DESTINATION "${LEAN_OLEAN_STAGING}/${_dir}/")
            endforeach()

            # Embed Init .olean files only via --embed-file (baked into JS).
            # Std/Lean/Sparkle are too large to embed (~800MB total) and
            # are instead loaded dynamically at runtime via fetch+FS.writeFile
            # (see src/pre.js). Their .olean files are installed to the
            # wasm-host prefix and served as static assets by JupyterLite.
            set(LEAN_OLEAN_STAGING_ROOT "${CMAKE_BINARY_DIR}/olean_staging")
            target_link_options(xlean
                PUBLIC "SHELL: --embed-file ${LEAN_OLEAN_STAGING_ROOT}@/")

            message(STATUS "Init .olean files will be embedded in WASM filesystem at /lib/lean/")

            # Std/Lean .olean files are NOT embedded (too large for WASM).
            # They are copied to a separate directory and installed as
            # static assets. The JS runtime fetches them on demand and
            # writes them into the emscripten VFS (see src/pre.js).
            set(OLEAN_ASSETS_DIR "${CMAKE_BINARY_DIR}/olean_assets/lib/lean")
            file(MAKE_DIRECTORY "${OLEAN_ASSETS_DIR}")

            # Copy Std .olean + .olean.server + .olean.private + .ir + .ilean
            # NOTE: .olean.server is required because Lean's findOLeanParts
            # only loads .olean.private if .olean.server exists alongside it.
            if(EXISTS "${LEAN_OLEAN_SRC}/Std.olean")
                foreach(_ext olean olean.server olean.private ir ilean)
                    if(EXISTS "${LEAN_OLEAN_SRC}/Std.${_ext}")
                        file(COPY "${LEAN_OLEAN_SRC}/Std.${_ext}" DESTINATION "${OLEAN_ASSETS_DIR}/")
                    endif()
                endforeach()
                file(GLOB_RECURSE _STD_FILES RELATIVE "${LEAN_OLEAN_SRC}"
                    "${LEAN_OLEAN_SRC}/Std/*.olean" "${LEAN_OLEAN_SRC}/Std/*.olean.server"
                    "${LEAN_OLEAN_SRC}/Std/*.olean.private"
                    "${LEAN_OLEAN_SRC}/Std/*.ir" "${LEAN_OLEAN_SRC}/Std/*.ilean")
                list(LENGTH _STD_FILES _std_count)
                message(STATUS "Std: ${_std_count} files → olean_assets (dynamic load)")
                foreach(_f ${_STD_FILES})
                    get_filename_component(_dir "${_f}" DIRECTORY)
                    file(MAKE_DIRECTORY "${OLEAN_ASSETS_DIR}/${_dir}")
                    file(COPY "${LEAN_OLEAN_SRC}/${_f}" DESTINATION "${OLEAN_ASSETS_DIR}/${_dir}/")
                endforeach()
            endif()

            # Copy Lean .olean + .olean.server + .olean.private + .ir + .ilean
            if(EXISTS "${LEAN_OLEAN_SRC}/Lean.olean")
                foreach(_ext olean olean.server olean.private ir ilean)
                    if(EXISTS "${LEAN_OLEAN_SRC}/Lean.${_ext}")
                        file(COPY "${LEAN_OLEAN_SRC}/Lean.${_ext}" DESTINATION "${OLEAN_ASSETS_DIR}/")
                    endif()
                endforeach()
                file(GLOB_RECURSE _LEAN_FILES RELATIVE "${LEAN_OLEAN_SRC}"
                    "${LEAN_OLEAN_SRC}/Lean/*.olean" "${LEAN_OLEAN_SRC}/Lean/*.olean.server"
                    "${LEAN_OLEAN_SRC}/Lean/*.olean.private"
                    "${LEAN_OLEAN_SRC}/Lean/*.ir" "${LEAN_OLEAN_SRC}/Lean/*.ilean")
                list(LENGTH _LEAN_FILES _lean_count)
                message(STATUS "Lean: ${_lean_count} files → olean_assets (dynamic load)")
                foreach(_f ${_LEAN_FILES})
                    get_filename_component(_dir "${_f}" DIRECTORY)
                    file(MAKE_DIRECTORY "${OLEAN_ASSETS_DIR}/${_dir}")
                    file(COPY "${LEAN_OLEAN_SRC}/${_f}" DESTINATION "${OLEAN_ASSETS_DIR}/${_dir}/")
                endforeach()
            endif()

            # Also embed Display.olean (from the project's .lake build)
            # so that the REPL can `import Display` at runtime. This makes
            # #html / #latex / #md / #svg / #json commands available to
            # user cells without an explicit import.
            #
            # CommBus is imported by Display, so its olean must be in the
            # VFS too — otherwise `import Display` fails at the header
            # stage with "unknown module prefix 'CommBus'", which then
            # cascades into Init/Std/Lean/Sparkle being skipped and the
            # cell crashing on basic identifiers like `IO.println`.
            set(DISPLAY_OLEAN_SRC "${CMAKE_SOURCE_DIR}/.lake/build/lib/lean")
            foreach(_mod Display CommBus)
                foreach(_ext olean olean.server olean.private ir)
                    if(EXISTS "${DISPLAY_OLEAN_SRC}/${_mod}.${_ext}")
                        file(COPY "${DISPLAY_OLEAN_SRC}/${_mod}.${_ext}" DESTINATION "${LEAN_OLEAN_STAGING}/")
                        message(STATUS "Embedding ${_mod}.${_ext} in WASM VFS")
                    endif()
                endforeach()
            endforeach()
            # Copy Sparkle .olean to assets (dynamic load, not embed)
            set(SPARKLE_OLEAN_SRC "${CMAKE_SOURCE_DIR}/examples/sparkle/.lake/packages/sparkle/.lake/build/lib/lean")
            if(IS_DIRECTORY "${SPARKLE_OLEAN_SRC}/Sparkle")
                foreach(_ext olean olean.private)
                    if(EXISTS "${SPARKLE_OLEAN_SRC}/Sparkle.${_ext}")
                        file(COPY "${SPARKLE_OLEAN_SRC}/Sparkle.${_ext}" DESTINATION "${OLEAN_ASSETS_DIR}/")
                    endif()
                endforeach()
                file(GLOB_RECURSE _SPARKLE_FILES RELATIVE "${SPARKLE_OLEAN_SRC}"
                    "${SPARKLE_OLEAN_SRC}/Sparkle/*.olean"
                    "${SPARKLE_OLEAN_SRC}/Sparkle/*.olean.server"
                    "${SPARKLE_OLEAN_SRC}/Sparkle/*.olean.private"
                    "${SPARKLE_OLEAN_SRC}/Sparkle/*.ir"
                    "${SPARKLE_OLEAN_SRC}/Sparkle/*.ilean")
                list(LENGTH _SPARKLE_FILES _sparkle_count)
                foreach(_f ${_SPARKLE_FILES})
                    get_filename_component(_dir "${_f}" DIRECTORY)
                    file(MAKE_DIRECTORY "${OLEAN_ASSETS_DIR}/${_dir}")
                    file(COPY "${SPARKLE_OLEAN_SRC}/${_f}" DESTINATION "${OLEAN_ASSETS_DIR}/${_dir}/")
                endforeach()
                message(STATUS "Sparkle: ${_sparkle_count} files → olean_assets (dynamic load)")
            else()
                message(STATUS "Sparkle .olean not found")
            endif()

            # Generate manifest.json listing all .olean asset files
            file(GLOB_RECURSE _ALL_ASSET_FILES
                RELATIVE "${CMAKE_BINARY_DIR}/olean_assets/lib/lean"
                "${CMAKE_BINARY_DIR}/olean_assets/lib/lean/*.olean"
                "${CMAKE_BINARY_DIR}/olean_assets/lib/lean/*.olean.server"
                "${CMAKE_BINARY_DIR}/olean_assets/lib/lean/*.olean.private"
                "${CMAKE_BINARY_DIR}/olean_assets/lib/lean/*.ir"
                "${CMAKE_BINARY_DIR}/olean_assets/lib/lean/*.ilean")
            # Write JSON array
            set(_manifest_json "[")
            set(_first TRUE)
            foreach(_f ${_ALL_ASSET_FILES})
                if(_first)
                    set(_first FALSE)
                else()
                    string(APPEND _manifest_json ",")
                endif()
                string(APPEND _manifest_json "\"${_f}\"")
            endforeach()
            string(APPEND _manifest_json "]")
            file(WRITE "${CMAKE_BINARY_DIR}/olean_assets/lib/lean/manifest.json" "${_manifest_json}")
            list(LENGTH _ALL_ASSET_FILES _total_assets)
            message(STATUS "Generated olean manifest: ${_total_assets} files")

            # Install olean_assets so they're served as static files.
            install(DIRECTORY "${CMAKE_BINARY_DIR}/olean_assets/lib/lean/"
                    DESTINATION "share/jupyter/olean"
                    OPTIONAL)
        else()
            message(WARNING "Init.olean not found at ${LEAN_OLEAN_SRC}/Init.olean - WASM kernel will have no Init module")
        endif()
    else()
        message(WARNING "Lean toolchain not found. Set -DLEAN_TOOLCHAIN_DIR=<path> to embed .olean files.")
    endif()

    # Generate WASM symbol lookup table
    # ==================================
    # In WASM, dlsym doesn't work without -sMAIN_MODULE.
    # We generate a static lookup table from all symbols in our libraries.
    include(GenerateSymbolTable)
    set(WASM_SYMTAB_FILE "${CMAKE_BINARY_DIR}/wasm_symbol_table.cpp")
    set(_symtab_libs
        ${LEANRT_LIB}
        ${STAGE0_INIT_LIB}
        ${STAGE0_STD_LIB}
        ${STAGE0_LEAN_LIB}
        ${STAGE0_REPL_LIB}
    )
    if(TARGET sparkle_wasm)
        list(APPEND _symtab_libs sparkle_wasm)
    endif()
    generate_wasm_symbol_table(${WASM_SYMTAB_FILE} ${_symtab_libs})

    # Add symbol table to xlean (generated above)
    target_sources(xlean PRIVATE ${WASM_SYMTAB_FILE})

    # Node.js test executable (standalone, no xeus dependency)
    # ========================================================

    add_executable(test_wasm_node test_wasm_node.cpp ${WASM_SYMTAB_FILE})
    target_include_directories(test_wasm_node PRIVATE ${LEAN4_INCLUDE_DIR})
    target_link_libraries(test_wasm_node PRIVATE
        ${STAGE0_REPL_LIB}
        ${STAGE0_LEAN_LIB}
        ${STAGE0_STD_LIB}
        ${STAGE0_INIT_LIB}
        ${LEANRT_LIB}
    )
    if(TARGET sparkle_wasm)
        # wasm_symbol_table.cpp references initialize_sparkle_* — needs
        # the Sparkle archive to resolve those symbols.
        target_link_options(test_wasm_node PRIVATE
            "SHELL: -Wl,--whole-archive ${CMAKE_BINARY_DIR}/libsparkle_wasm.a -Wl,--no-whole-archive"
        )
        add_dependencies(test_wasm_node sparkle_wasm)
    endif()
    target_compile_options(test_wasm_node PRIVATE -fPIC -g2)
    target_link_options(test_wasm_node PRIVATE
        "SHELL: -fwasm-exceptions"
        "SHELL: -sALLOW_MEMORY_GROWTH=1"
        "SHELL: -sINITIAL_MEMORY=4096mb"
        "SHELL: -sMAXIMUM_MEMORY=4gb"
        "SHELL: -sSTACK_SIZE=64mb"
        "SHELL: -sFORCE_FILESYSTEM"
        "SHELL: -sENVIRONMENT=node"
        "SHELL: -sEXIT_RUNTIME=0"
        "SHELL: -sASSERTIONS=0"
        "SHELL: -sNODERAWFS=0"
        "SHELL: -sWASM_BIGINT"
        "SHELL: -sEXPORTED_FUNCTIONS=_main"
        "SHELL: -sEXPORTED_RUNTIME_METHODS=FS,ENV,PATH"
        "SHELL: -sEXPORT_ALL=1"
        "SHELL: --profiling-funcs"
    )
    # test_wasm_node only needs Init .olean files (not Std/Lean/Sparkle).
    # Create a minimal staging with Init only to keep the binary small.
    if(LEAN_TOOLCHAIN_DIR AND EXISTS "${LEAN_OLEAN_SRC}/Init.olean")
        set(TEST_OLEAN_STAGING "${CMAKE_BINARY_DIR}/test_olean_staging/lib/lean")
        file(MAKE_DIRECTORY "${TEST_OLEAN_STAGING}")
        # Use shell `cp` instead of cmake file(COPY) which is O(n) syscalls
        # and can take 15+ minutes on slow filesystems for 2K+ files.
        # Includes .olean (kernel), .olean.server (server data), .olean.private,
        # and .ir / .ilean — all needed for module imports in the WASM REPL.
        execute_process(
            COMMAND sh -c "cp -f \"${LEAN_OLEAN_SRC}\"/Init.olean \"${LEAN_OLEAN_SRC}\"/Init.olean.server \"${LEAN_OLEAN_SRC}\"/Init.olean.private \"${LEAN_OLEAN_SRC}\"/Init.ir \"${LEAN_OLEAN_SRC}\"/Init.ilean \"${TEST_OLEAN_STAGING}/\" 2>/dev/null; cp -rf \"${LEAN_OLEAN_SRC}/Init\" \"${TEST_OLEAN_STAGING}/\""
            RESULT_VARIABLE _cp_rc)
        if(_cp_rc)
            message(WARNING "Init staging copy failed: rc=${_cp_rc}")
        endif()
        target_link_options(test_wasm_node
            PUBLIC "SHELL: --embed-file ${CMAKE_BINARY_DIR}/test_olean_staging@/")
    endif()

    # Installation
    # ============

    # Install WASM artifacts
    install(TARGETS xlean
            ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})

    install(FILES
            "$<TARGET_FILE_DIR:xlean>/xlean.js"
            "$<TARGET_FILE_DIR:xlean>/xlean.wasm"
            DESTINATION ${CMAKE_INSTALL_BINDIR})

    # --preload-file generates xlean.data containing all .olean files.
    # It must be served alongside xlean.js for the VFS to work.
    install(FILES "$<TARGET_FILE_DIR:xlean>/xlean.data"
            DESTINATION ${CMAKE_INSTALL_BINDIR}
            OPTIONAL)

    # Install kernel spec
    set(XJUPYTER_DATA_DIR "share/jupyter" CACHE STRING "Jupyter data directory")
    set(KERNELSPEC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/share/jupyter/kernels)
    install(DIRECTORY ${KERNELSPEC_DIR}
            DESTINATION ${XJUPYTER_DATA_DIR}
            PATTERN "*.in" EXCLUDE)

# ============================================================================
# NATIVE BUILD (existing)
# ============================================================================

else()
    message(STATUS "Building xeus-lean native FFI library")

    # Dependencies
    # ============

    include(FetchContent)

    # Use system nlohmann_json if available
    find_package(nlohmann_json QUIET)
    if(NOT nlohmann_json_FOUND)
        message(STATUS "System nlohmann_json not found, fetching from GitHub...")
        FetchContent_Declare(
            nlohmann_json
            GIT_REPOSITORY https://github.com/nlohmann/json.git
            GIT_TAG v3.11.3
        )
        FetchContent_MakeAvailable(nlohmann_json)
        set(JSON_TARGET nlohmann_json)
    else()
        set(JSON_TARGET nlohmann_json::nlohmann_json)
    endif()

    # Fetch xtl (required by xeus)
    FetchContent_Declare(
        xtl
        GIT_REPOSITORY https://github.com/xtensor-stack/xtl.git
        GIT_TAG 0.7.7
    )

    # Fetch xeus
    FetchContent_Declare(
        xeus
        GIT_REPOSITORY https://github.com/jupyter-xeus/xeus.git
        GIT_TAG 5.1.0
    )

    # Try to find system ZeroMQ first
    find_package(ZeroMQ QUIET)
    find_package(cppzmq QUIET)

    if(NOT ZeroMQ_FOUND)
        message(STATUS "System ZeroMQ not found, fetching from GitHub...")
        set(WITH_PERF_TOOL OFF CACHE BOOL "")
        set(ZMQ_BUILD_TESTS OFF CACHE BOOL "")
        set(ENABLE_CPACK OFF CACHE BOOL "")
        set(BUILD_TESTS OFF CACHE BOOL "")

        FetchContent_Declare(
            libzmq
            GIT_REPOSITORY https://github.com/zeromq/libzmq.git
            GIT_TAG v4.3.5
        )
        FetchContent_MakeAvailable(libzmq)
    endif()

    if(NOT cppzmq_FOUND)
        message(STATUS "System cppzmq not found, fetching from GitHub...")
        set(CPPZMQ_BUILD_TESTS OFF CACHE BOOL "")

        FetchContent_Declare(
            cppzmq
            GIT_REPOSITORY https://github.com/zeromq/cppzmq.git
            GIT_TAG v4.10.0
        )
        FetchContent_MakeAvailable(cppzmq)
    endif()

    # Help xeus-zmq find FetchContent-built ZeroMQ/cppzmq via find_package()
    if(NOT ZeroMQ_FOUND)
        set(ZeroMQ_DIR "${CMAKE_BINARY_DIR}/_deps/libzmq-build" CACHE PATH "" FORCE)
    endif()
    if(NOT cppzmq_FOUND)
        set(cppzmq_DIR "${CMAKE_BINARY_DIR}/_deps/cppzmq-build" CACHE PATH "" FORCE)
    endif()

    # Fetch xeus-zmq
    FetchContent_Declare(
        xeus-zmq
        GIT_REPOSITORY https://github.com/jupyter-xeus/xeus-zmq.git
        GIT_TAG 3.0.0
    )

    message(STATUS "Fetching dependencies from GitHub...")
    FetchContent_MakeAvailable(xtl xeus xeus-zmq)
    message(STATUS "Dependencies fetched successfully")

    # Lean Integration
    # ================

    # Find Lean installation
    find_program(LEAN_EXECUTABLE lean REQUIRED)

    execute_process(
        COMMAND ${LEAN_EXECUTABLE} --print-prefix
        OUTPUT_VARIABLE LEAN_PREFIX
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )

    message(STATUS "Found Lean at: ${LEAN_PREFIX}")

    # Set Lean include and library paths
    set(LEAN_INCLUDE_DIR "${LEAN_PREFIX}/include")
    set(LEAN_LIB_DIR "${LEAN_PREFIX}/lib/lean")

    # Find Lean runtime libraries
    find_library(LEAN_LIBRARY NAMES leanshared lean PATHS ${LEAN_LIB_DIR} REQUIRED)

    message(STATUS "Lean library: ${LEAN_LIBRARY}")
    message(STATUS "Lean include dir: ${LEAN_INCLUDE_DIR}")

    # xeus FFI library (for Lean to call)
    # ====================================

    add_library(xeus_ffi STATIC src/xeus_ffi.cpp)
    target_compile_features(xeus_ffi PRIVATE cxx_std_17)

    # Link with xeus
    target_link_libraries(xeus_ffi PUBLIC xeus-static)
    target_link_libraries(xeus_ffi PUBLIC xeus-zmq)
    target_link_libraries(xeus_ffi PUBLIC ${JSON_TARGET})
    target_include_directories(xeus_ffi PUBLIC ${LEAN_INCLUDE_DIR})
    target_link_libraries(xeus_ffi PUBLIC ${LEAN_LIBRARY})

    find_package(Threads)
    target_link_libraries(xeus_ffi PRIVATE ${CMAKE_THREAD_LIBS_INIT})

    # Set rpath for the FFI library
    set_target_properties(xeus_ffi PROPERTIES
        BUILD_WITH_INSTALL_RPATH TRUE
        INSTALL_RPATH "${LEAN_LIB_DIR};${CMAKE_BINARY_DIR}/_deps/xeus-build;${CMAKE_BINARY_DIR}/_deps/xeus-zmq-build"
        INSTALL_RPATH_USE_LINK_PATH TRUE
    )

    message(STATUS "xeus FFI library configured")

endif()
