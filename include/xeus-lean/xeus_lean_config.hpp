/***************************************************************************
* Copyright (c) 2025, xeus-lean contributors
*
* Distributed under the terms of the Apache Software License 2.0.
*
* The full license is in the file LICENSE, distributed with this software.
****************************************************************************/

#ifndef XEUS_LEAN_CONFIG_HPP
#define XEUS_LEAN_CONFIG_HPP

#define XEUS_LEAN_VERSION_MAJOR 0
#define XEUS_LEAN_VERSION_MINOR 1
#define XEUS_LEAN_VERSION_PATCH 0

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
