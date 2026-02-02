/***************************************************************************
* Copyright (c) 2025, xeus-lean contributors
*
* Distributed under the terms of the Apache Software License 2.0.
*
* The full license is in the file LICENSE, distributed with this software.
****************************************************************************/

#ifndef XEUS_LEAN_CONFIG_HPP
#define XEUS_LEAN_CONFIG_HPP

// Project version
#define XEUS_LEAN_VERSION_MAJOR 0
#define XEUS_LEAN_VERSION_MINOR 1
#define XEUS_LEAN_VERSION_PATCH 0

// Construct the version string
#define XEUS_LEAN_CONCATENATE(A, B) XEUS_LEAN_CONCATENATE_IMPL(A, B)
#define XEUS_LEAN_CONCATENATE_IMPL(A, B) A##B
#define XEUS_LEAN_STRINGIFY(a) XEUS_LEAN_STRINGIFY_IMPL(a)
#define XEUS_LEAN_STRINGIFY_IMPL(a) #a

#define XEUS_LEAN_VERSION XEUS_LEAN_STRINGIFY(XEUS_LEAN_CONCATENATE(XEUS_LEAN_VERSION_MAJOR,     \
                 XEUS_LEAN_CONCATENATE(.,XEUS_LEAN_CONCATENATE(XEUS_LEAN_VERSION_MINOR,   \
                 XEUS_LEAN_CONCATENATE(.,XEUS_LEAN_VERSION_PATCH)))))

#ifdef _WIN32
    #ifdef XEUS_LEAN_EXPORTS
        #define XEUS_LEAN_API __declspec(dllexport)
    #else
        #define XEUS_LEAN_API __declspec(dllimport)
    #endif
#else
    #define XEUS_LEAN_API __attribute__((visibility("default")))
#endif

#endif
