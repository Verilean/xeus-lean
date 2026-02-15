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

    add_executable(xlean src/main_emscripten_kernel.cpp)
    target_link_libraries(xlean PRIVATE xeus-lite)
    target_link_libraries(xlean PRIVATE xeus-lean-static)
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
    )

    target_link_options(xlean
        PUBLIC "SHELL: --pre-js ${CMAKE_CURRENT_SOURCE_DIR}/src/pre.js"
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

            # Copy top-level Init files
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

            # Embed via emscripten --embed-file (data baked into JS, no separate fetch)
            # Maps staging/lib/lean/* -> /lib/lean/* in WASM VFS
            set(LEAN_OLEAN_STAGING_ROOT "${CMAKE_BINARY_DIR}/olean_staging")
            target_link_options(xlean
                PUBLIC "SHELL: --embed-file ${LEAN_OLEAN_STAGING_ROOT}@/")

            message(STATUS "Init .olean files will be embedded in WASM filesystem at /lib/lean/")
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
    generate_wasm_symbol_table(${WASM_SYMTAB_FILE}
        ${LEANRT_LIB}
        ${STAGE0_INIT_LIB}
        ${STAGE0_STD_LIB}
        ${STAGE0_LEAN_LIB}
        ${STAGE0_REPL_LIB}
    )

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
    target_compile_options(test_wasm_node PRIVATE -fPIC -g2)
    target_link_options(test_wasm_node PRIVATE
        "SHELL: -fwasm-exceptions"
        "SHELL: -sALLOW_MEMORY_GROWTH=1"
        "SHELL: -sINITIAL_MEMORY=1024mb"
        "SHELL: -sMAXIMUM_MEMORY=4gb"
        "SHELL: -sSTACK_SIZE=64mb"
        "SHELL: -sFORCE_FILESYSTEM"
        "SHELL: -sENVIRONMENT=node"
        "SHELL: -sEXIT_RUNTIME=1"
        "SHELL: -sASSERTIONS=2"
        "SHELL: -sNODERAWFS=0"
        "SHELL: -sWASM_BIGINT"
        "SHELL: -sEXPORTED_FUNCTIONS=_main"
        "SHELL: -sEXPORTED_RUNTIME_METHODS=FS,ENV,PATH"
        "SHELL: -sEXPORT_ALL=1"
        "SHELL: --profiling-funcs"
    )
    # Embed olean files for Init module loading
    if(LEAN_TOOLCHAIN_DIR AND EXISTS "${LEAN_OLEAN_STAGING}")
        target_link_options(test_wasm_node
            PUBLIC "SHELL: --embed-file ${CMAKE_BINARY_DIR}/olean_staging@/")
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

    # Note: .olean files are embedded in xlean.js via --embed-file, no separate .data file

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
