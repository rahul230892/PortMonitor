#ifndef CPROC_SOCKETS_H
#define CPROC_SOCKETS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * One open TCP/UDP socket owned by a local process, resolved through libproc.
 * Fixed-size buffers keep this trivially importable from Swift.
 */
typedef struct {
    int32_t  pid;          /* owning process id            */
    int32_t  uid;          /* owning user id               */
    int32_t  fd;           /* file descriptor number       */
    int32_t  family;       /* AF_INET / AF_INET6           */
    int32_t  protocol;     /* IPPROTO_TCP / IPPROTO_UDP    */
    int32_t  state;        /* tcpsi_state for TCP, 0 for UDP */
    uint16_t port;         /* local port, host byte order  */
    char     address[64];  /* local address, or "*"        */
    char     name[256];    /* process name                 */
} cps_socket_t;

/*
 * Collects listening TCP sockets and bound UDP sockets.
 *
 * Writes at most `max` entries into `out` and returns the total number of
 * matching sockets (which may exceed `max`). Pass `out == NULL, max == 0` to
 * query the current count. Returns -1 on failure.
 */
int32_t cps_list_sockets(cps_socket_t *out, int32_t max);

#ifdef __cplusplus
}
#endif

#endif /* CPROC_SOCKETS_H */
