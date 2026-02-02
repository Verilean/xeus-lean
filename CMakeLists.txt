############################################################################
# Copyright (c) 2025, xeus-lean contributors
#
# Distributed under the terms of the Apache Software License 2.0.
#
# The full license is in the file LICENSE, distributed with this software.
############################################################################

cmake_minimum_required(VERSION 3.10.0)
project(xeus-lean)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake;${CMAKE_MODULE_PATH}")

set(XEUS_LEAN_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)

# Versioning
# ==========

file(STRINGS "${XEUS_LEAN_INCLUDE_DIR}/xeus-lean/xeus_lean_config.hpp" version_defines
     REGEX "#define XEUS_LEAN_VERSION_(MAJOR|MINOR|PATCH)")
foreach (ver ${version_defines})
    if (ver MATCHES "#define XEUS_LEAN_VERSION_(MAJOR|MINOR|PATCH) +([^ ]+)$")
        set(XEUS_LEAN_VERSION_${CMAKE_MATCH_1} "${CMAKE_MATCH_2}" CACHE INTERNAL "")
    endif ()
endforeach ()
set(${PROJECT_NAME}_VERSION
    ${XEUS_LEAN_VERSION_MAJOR}.${XEUS_LEAN_VERSION_MINOR}.${XEUS_LEAN_VERSION_PATCH})
message(STATUS "Building xeus-lean v${${PROJECT_NAME}_VERSION}")

# Configuration
# =============

include(GNUInstallDirs)

if (NOT DEFINED XEUS_LEAN_KERNELSPEC_PATH)
    set(XEUS_LEAN_KERNELSPEC_PATH "${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_BINDIR}/")
endif ()

configure_file (
    "${CMAKE_CURRENT_SOURCE_DIR}/share/jupyter/kernels/xlean/kernel.json.in"
    "${CMAKE_CURRENT_SOURCE_DIR}/share/jupyter/kernels/xlean/kernel.json"
)

# Build options
# =============

OPTION(XEUS_LEAN_BUILD_STATIC "Build xeus-lean static library" ON)
OPTION(XEUS_LEAN_BUILD_SHARED "Build xeus-lean shared library" OFF)
OPTION(XEUS_LEAN_BUILD_EXECUTABLE "Build the xlean executable" ON)
OPTION(XEUS_LEAN_USE_SHARED_XEUS "Link xlean with the xeus shared library" ON)
OPTION(XEUS_LEAN_USE_SHARED_XEUS_LEAN "Link xlean with the xeus-lean shared library" OFF)

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
find_program(LAKE_EXECUTABLE lake REQUIRED)

execute_process(
    COMMAND ${LEAN_EXECUTABLE} --print-prefix
    OUTPUT_VARIABLE LEAN_PREFIX
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

message(STATUS "Found Lean at: ${LEAN_PREFIX}")

# Set Lean include and library paths
set(LEAN_INCLUDE_DIR "${LEAN_PREFIX}/include")
set(LEAN_LIB_DIR "${LEAN_PREFIX}/lib/lean")

# Build Lean REPL module (unless already built by Lake)
if(NOT SKIP_LAKE_BUILD)
    message(STATUS "Building Lean REPL module...")
    execute_process(
        COMMAND ${LAKE_EXECUTABLE} build ReplFFI
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        RESULT_VARIABLE LAKE_BUILD_RESULT
    )

    if(NOT LAKE_BUILD_RESULT EQUAL 0)
        message(FATAL_ERROR "Failed to build Lean REPL module")
    endif()
else()
    message(STATUS "Skipping Lake build (already done)")
endif()

# Find all generated C files from Lean modules
file(GLOB_RECURSE REPL_C_FILES "${CMAKE_CURRENT_SOURCE_DIR}/.lake/build/ir/*.c")

# Exclude Main.c because it has its own main() function
list(FILTER REPL_C_FILES EXCLUDE REGEX ".*/REPL/Main\\.c$")

if(NOT REPL_C_FILES)
    message(FATAL_ERROR "No .c files found in .lake/build/ir/")
endif()

list(LENGTH REPL_C_FILES REPL_C_COUNT)
message(STATUS "Found ${REPL_C_COUNT} Lean C files (excluding Main.c)")

# Create ReplFFI library from all generated C code
add_library(repl_ffi STATIC ${REPL_C_FILES})
target_include_directories(repl_ffi PUBLIC ${LEAN_INCLUDE_DIR})
target_compile_options(repl_ffi PRIVATE -fPIC)

# Find Lean runtime libraries
find_library(LEAN_LIBRARY NAMES leanshared lean PATHS ${LEAN_LIB_DIR} REQUIRED)
find_library(LEANRT_LIBRARY NAMES leancpp leanrt PATHS ${LEAN_LIB_DIR})

message(STATUS "Lean library: ${LEAN_LIBRARY}")
message(STATUS "Lean include dir: ${LEAN_INCLUDE_DIR}")

# Flags
# =====

if (MSVC)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /wd4251 /wd4141")
endif ()

if (CMAKE_CXX_COMPILER_ID MATCHES "Clang" OR CMAKE_CXX_COMPILER_ID MATCHES "GNU")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wunused-parameter -Wextra -Wreorder")
endif ()

# Source files
# ============

set(XEUS_LEAN_HEADERS
    include/xeus-lean/xeus_lean_config.hpp
    include/xeus-lean/xinterpreter.hpp
    include/xeus-lean/lean_repl.hpp
)

set(XEUS_LEAN_SRC
    src/xinterpreter.cpp
    src/lean_repl.cpp
)

set(XEUS_LEAN_MAIN_SRC
    src/main.cpp
)

# Targets and link
# ================

set(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_PREFIX}/lib;${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}")

macro(xeus_lean_set_common_options target_name)
    if (MSVC)
        target_compile_options(${target_name} PUBLIC /wd4251 /wd4141)
    endif ()

    if (CMAKE_CXX_COMPILER_ID MATCHES "Clang" OR
        CMAKE_CXX_COMPILER_ID MATCHES "GNU")
        target_compile_options(${target_name} PUBLIC -Wunused-parameter -Wextra -Wreorder)
    endif ()

    if (APPLE)
        set_target_properties(${target_name} PROPERTIES
            MACOSX_RPATH ON
        )
    else ()
        set_target_properties(${target_name} PROPERTIES
            BUILD_WITH_INSTALL_RPATH 1
            SKIP_BUILD_RPATH FALSE
        )
    endif ()

    set_target_properties(${target_name} PROPERTIES
        INSTALL_RPATH_USE_LINK_PATH TRUE
    )
endmacro()

# Common macro for shared and static library
macro(xeus_lean_create_target target_name linkage output_name)
    string(TOUPPER "${linkage}" linkage_upper)

    if (NOT ${linkage_upper} MATCHES "^(SHARED|STATIC)$")
        message(FATAL_ERROR "Invalid library linkage: ${linkage}")
    endif ()

    add_library(${target_name} ${linkage_upper} ${XEUS_LEAN_SRC} ${XEUS_LEAN_HEADERS})
    xeus_lean_set_common_options(${target_name})

    set_target_properties(${target_name} PROPERTIES
                          PUBLIC_HEADER "${XEUS_LEAN_HEADERS}"
                          PREFIX ""
                          VERSION ${${PROJECT_NAME}_VERSION}
                          SOVERSION ${XEUS_LEAN_VERSION_MAJOR}
                          OUTPUT_NAME "lib${output_name}")

    target_compile_definitions(${target_name} PUBLIC XEUS_LEAN_EXPORTS)
    target_compile_features(${target_name} PRIVATE cxx_std_17)

    target_include_directories(${target_name}
                               PUBLIC
                               $<BUILD_INTERFACE:${XEUS_LEAN_INCLUDE_DIR}>
                               $<INSTALL_INTERFACE:include>)

    if (XEUS_LEAN_USE_SHARED_XEUS)
        set(XEUS_LEAN_XEUS_TARGET xeus)
    else ()
        set(XEUS_LEAN_XEUS_TARGET xeus-static)
    endif ()

    target_link_libraries(${target_name} PUBLIC ${XEUS_LEAN_XEUS_TARGET})
    target_link_libraries(${target_name} PUBLIC ${JSON_TARGET})

    # Link Lean libraries
    target_include_directories(${target_name} PUBLIC ${LEAN_INCLUDE_DIR})
    target_link_libraries(${target_name} PUBLIC repl_ffi)
    target_link_libraries(${target_name} PUBLIC ${LEAN_LIBRARY})
    if(LEANRT_LIBRARY)
        target_link_libraries(${target_name} PUBLIC ${LEANRT_LIBRARY})
    endif()

    if (APPLE)
        target_link_libraries(${target_name} PRIVATE "-undefined dynamic_lookup")
    endif ()

    find_package(Threads)
    target_link_libraries(${target_name} PRIVATE ${CMAKE_THREAD_LIBS_INIT})
endmacro()

# xeus-lean library
# =================

set(XEUS_LEAN_TARGETS "")

if (XEUS_LEAN_BUILD_SHARED)
    xeus_lean_create_target(xeus-lean SHARED xeus-lean)
    list(APPEND XEUS_LEAN_TARGETS xeus-lean)
endif ()

if (XEUS_LEAN_BUILD_STATIC)
    if (CMAKE_HOST_WIN32)
        xeus_lean_create_target(xeus-lean-static STATIC xeus-lean-static)
    else ()
        xeus_lean_create_target(xeus-lean-static STATIC xeus-lean)
    endif ()
    list(APPEND XEUS_LEAN_TARGETS xeus-lean-static)
endif ()

# xeus FFI library (for Lean to call)
# ====================================

add_library(xeus_ffi STATIC src/xeus_ffi.cpp)
target_compile_features(xeus_ffi PRIVATE cxx_std_17)

# Link with xeus and lean
if (XEUS_LEAN_USE_SHARED_XEUS)
    set(XEUS_LEAN_XEUS_TARGET xeus)
else ()
    set(XEUS_LEAN_XEUS_TARGET xeus-static)
endif ()

target_link_libraries(xeus_ffi PUBLIC ${XEUS_LEAN_XEUS_TARGET})
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

# xlean executable
# ================

if (XEUS_LEAN_BUILD_EXECUTABLE)
    # xeus-zmq already fetched via FetchContent above

    add_executable(xlean ${XEUS_LEAN_MAIN_SRC})
    target_compile_features(xlean PRIVATE cxx_std_17)
    xeus_lean_set_common_options(xlean)

    if (XEUS_LEAN_USE_SHARED_XEUS_LEAN)
        target_link_libraries(xlean PRIVATE xeus-lean)
    else ()
        target_link_libraries(xlean PRIVATE xeus-lean-static)
    endif()

    target_link_libraries(xlean PRIVATE xeus-zmq)

    find_package(Threads)
    target_link_libraries(xlean PRIVATE ${CMAKE_THREAD_LIBS_INIT})

    # Set rpath for finding shared libraries
    set_target_properties(xlean PROPERTIES
        BUILD_WITH_INSTALL_RPATH TRUE
        INSTALL_RPATH "${LEAN_LIB_DIR};${CMAKE_BINARY_DIR}/_deps/xeus-build;${CMAKE_BINARY_DIR}/_deps/xeus-zmq-build;${CMAKE_INSTALL_PREFIX}/lib"
        INSTALL_RPATH_USE_LINK_PATH TRUE
    )
endif()

# Installation
# ============

include(CMakePackageConfigHelpers)

set(XEUS_LEAN_CMAKECONFIG_INSTALL_DIR "${CMAKE_INSTALL_LIBDIR}/cmake/${PROJECT_NAME}" CACHE STRING "install path for xeus-leanConfig.cmake")

# Note: Library installation disabled to avoid export complexities
# Only the xlean executable is needed for the Jupyter kernel
# if (XEUS_LEAN_BUILD_SHARED OR XEUS_LEAN_BUILD_STATIC)
#     install(TARGETS ${XEUS_LEAN_TARGETS}
#             EXPORT ${PROJECT_NAME}-targets
#             ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
#             LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
#             RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
#             PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/xeus-lean)
#
#     export(EXPORT ${PROJECT_NAME}-targets
#            FILE "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}Targets.cmake")
# endif ()

# Install xlean executable
if (XEUS_LEAN_BUILD_EXECUTABLE)
    install(TARGETS xlean
            RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

    # Install Jupyter kernelspec
    set(XJUPYTER_DATA_DIR "share/jupyter" CACHE STRING "Jupyter data directory")
    set(KERNELSPEC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/share/jupyter/kernels)
    install(DIRECTORY ${KERNELSPEC_DIR}
            DESTINATION ${XJUPYTER_DATA_DIR}
            PATTERN "*.in" EXCLUDE)
endif ()

# Package config installation disabled (library not exported)
# configure_package_config_file(
#     ${PROJECT_NAME}Config.cmake.in
#     "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}Config.cmake"
#     INSTALL_DESTINATION ${XEUS_LEAN_CMAKECONFIG_INSTALL_DIR}
# )
#
# write_basic_package_version_file(
#     ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}ConfigVersion.cmake
#     VERSION ${${PROJECT_NAME}_VERSION}
#     COMPATIBILITY AnyNewerVersion
# )
#
# install(FILES
#     ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}Config.cmake
#     ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}ConfigVersion.cmake
#     DESTINATION ${XEUS_LEAN_CMAKECONFIG_INSTALL_DIR}
# )
#
# if (XEUS_LEAN_BUILD_SHARED OR XEUS_LEAN_BUILD_STATIC)
#     install(EXPORT ${PROJECT_NAME}-targets
#             FILE ${PROJECT_NAME}Targets.cmake
#             DESTINATION ${XEUS_LEAN_CMAKECONFIG_INSTALL_DIR})
# endif ()
