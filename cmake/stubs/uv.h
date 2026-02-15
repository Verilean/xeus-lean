/*
 * Minimal libuv stub header for Lean4 runtime WASM/emscripten build.
 *
 * The Lean4 runtime has LEAN_EMSCRIPTEN guards for most libuv usage,
 * but some code (io.cpp, net_addr.cpp) references libuv types/functions
 * in unguarded paths. This header provides enough to compile; the stub
 * implementations in uv_stubs.c return errors at runtime.
 */
#pragma once

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Version */
#define UV_VERSION_MAJOR 1
#define UV_VERSION_MINOR 48
#define UV_VERSION_PATCH 0
#define UV_VERSION_HEX  ((UV_VERSION_MAJOR << 16) | (UV_VERSION_MINOR << 8) | UV_VERSION_PATCH)

/* Error codes (negative values, matching libuv convention) */
#define UV_EOF            (-4095)
#define UV_E2BIG          (-4093)
#define UV_EACCES         (-4092)
#define UV_EADDRINUSE     (-4091)
#define UV_EADDRNOTAVAIL  (-4090)
#define UV_EAFNOSUPPORT   (-4089)
#define UV_EAGAIN         (-4088)
#define UV_EALREADY       (-4084)
#define UV_EBADF          (-4083)
#define UV_EBUSY          (-4082)
#define UV_ECONNABORTED   (-4079)
#define UV_ECONNREFUSED   (-4078)
#define UV_ECONNRESET     (-4077)
#define UV_EDESTADDRREQ   (-4076)
#define UV_EEXIST          (-4075)
#define UV_EFAULT          (-4074)
#define UV_EFBIG           (-4073)
#define UV_EHOSTUNREACH    (-4072)
#define UV_EILSEQ          (-4071)
#define UV_EINTR           (-4070)
#define UV_EINVAL          (-4069)
#define UV_EIO             (-4068)
#define UV_EISCONN         (-4067)
#define UV_EISDIR          (-4066)
#define UV_ELOOP           (-4065)
#define UV_EMFILE          (-4064)
#define UV_EMLINK          (-4063)
#define UV_EMSGSIZE        (-4062)
#define UV_ENAMETOOLONG    (-4061)
#define UV_ENETDOWN        (-4060)
#define UV_ENETUNREACH     (-4059)
#define UV_ENFILE          (-4058)
#define UV_ENOBUFS         (-4057)
#define UV_ENODATA         (-4056)
#define UV_ENODEV          (-4055)
#define UV_ENOENT          (-4054)
#define UV_ENOMEM          (-4053)
#define UV_ENOPROTOOPT     (-4052)
#define UV_ENOSPC          (-4051)
#define UV_ENOSYS          (-4050)
#define UV_ENOTCONN        (-4049)
#define UV_ENOTDIR         (-4048)
#define UV_ENOTEMPTY       (-4047)
#define UV_ENOTSOCK        (-4046)
#define UV_ENOTSUP         (-4045)
#define UV_ENOTTY          (-4044)
#define UV_ENXIO           (-4043)
#define UV_EPERM           (-4042)
#define UV_EPIPE           (-4041)
#define UV_EPROTO          (-4040)
#define UV_EPROTONOSUPPORT (-4039)
#define UV_EPROTOTYPE      (-4038)
#define UV_ERANGE          (-4037)
#define UV_EROFS           (-4036)
#define UV_ESPIPE          (-4035)
#define UV_ESRCH           (-4034)
#define UV_ETIMEDOUT       (-4033)
#define UV_ETXTBSY         (-4032)
#define UV_EXDEV           (-4031)

/* Types used in unguarded code */

typedef struct uv_fs_s {
    ssize_t result;
    const char* path;
    /* internal */
    void* _data;
} uv_fs_t;

typedef struct uv_interface_address_s {
    char* name;
    char phys_addr[6];
    int is_internal;
    struct sockaddr_storage address;
    struct sockaddr_storage netmask;
} uv_interface_address_t;

/* Functions used in unguarded code */

const char* uv_strerror(int err);

/* Filesystem operations (used by io.cpp) */
int uv_fs_link(void* loop, uv_fs_t* req, const char* path, const char* new_path, void* cb);
int uv_fs_mkstemp(void* loop, uv_fs_t* req, const char* tpl, void* cb);
int uv_fs_mkdtemp(void* loop, uv_fs_t* req, const char* tpl, void* cb);
void uv_fs_req_cleanup(uv_fs_t* req);
int uv_os_tmpdir(char* buffer, size_t* size);

/* Network address operations (used by net_addr.cpp) */
int uv_inet_pton(int af, const char* src, void* dst);
int uv_inet_ntop(int af, const void* src, char* dst, size_t size);
int uv_interface_addresses(uv_interface_address_t** addresses, int* count);
void uv_free_interface_addresses(uv_interface_address_t* addresses, int count);

#ifdef __cplusplus
}
#endif
