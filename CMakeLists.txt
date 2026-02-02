############################################################################
# Copyright (c) 2025, xeus-lean contributors
#
# Distributed under the terms of the Apache Software License 2.0.
#
# The full license is in the file LICENSE, distributed with this software.
############################################################################

cmake_minimum_required(VERSION 3.10.0)
project(xeus-lean-ffi VERSION 0.1.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

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
