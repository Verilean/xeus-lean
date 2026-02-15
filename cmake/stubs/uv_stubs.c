/*
 * Minimal libuv stub implementations for Lean4 runtime WASM/emscripten build.
 * These functions are referenced by io.cpp and net_addr.cpp in code paths
 * that are NOT guarded by #ifndef LEAN_EMSCRIPTEN.
 */
#include "uv.h"
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <arpa/inet.h>

const char* uv_strerror(int err) {
    /* Return a generic error message for all UV error codes */
    switch (err) {
    case UV_ENOENT: return "no such file or directory";
    case UV_EACCES: return "permission denied";
    case UV_EINVAL: return "invalid argument";
    case UV_ENOSYS: return "function not implemented";
    case UV_ENOTSUP: return "operation not supported";
    default: return "unknown error (libuv stub)";
    }
}

int uv_fs_link(void* loop, uv_fs_t* req, const char* path, const char* new_path, void* cb) {
    (void)loop; (void)req; (void)path; (void)new_path; (void)cb;
    return UV_ENOSYS;
}

int uv_fs_mkstemp(void* loop, uv_fs_t* req, const char* tpl, void* cb) {
    (void)loop; (void)req; (void)tpl; (void)cb;
    return UV_ENOSYS;
}

int uv_fs_mkdtemp(void* loop, uv_fs_t* req, const char* tpl, void* cb) {
    (void)loop; (void)req; (void)tpl; (void)cb;
    return UV_ENOSYS;
}

void uv_fs_req_cleanup(uv_fs_t* req) {
    (void)req;
}

int uv_os_tmpdir(char* buffer, size_t* size) {
    const char* tmp = "/tmp";
    size_t len = strlen(tmp);
    if (*size <= len) {
        *size = len + 1;
        return UV_ENOBUFS;
    }
    memcpy(buffer, tmp, len + 1);
    *size = len;
    return 0;
}

int uv_inet_pton(int af, const char* src, void* dst) {
    int ret = inet_pton(af, src, dst);
    if (ret == 1) return 0;
    if (ret == 0) return UV_EINVAL;
    return UV_EAFNOSUPPORT;
}

int uv_inet_ntop(int af, const void* src, char* dst, size_t size) {
    if (inet_ntop(af, src, dst, (socklen_t)size) != NULL)
        return 0;
    return UV_ENOSPC;
}

int uv_interface_addresses(uv_interface_address_t** addresses, int* count) {
    *addresses = NULL;
    *count = 0;
    return UV_ENOSYS;
}

void uv_free_interface_addresses(uv_interface_address_t* addresses, int count) {
    (void)addresses; (void)count;
}
