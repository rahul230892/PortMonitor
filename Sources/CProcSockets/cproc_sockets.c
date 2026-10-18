#include "cproc_sockets.h"

#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp_fsm.h>
#include <arpa/inet.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Fills `buf` with the process name for `pid`, falling back to "pid N". */
static void fill_name(int32_t pid, char *buf, int32_t buflen)
{
    if (buflen <= 0) {
        return;
    }
    buf[0] = '\0';
    if (proc_name(pid, buf, (uint32_t)buflen) <= 0) {
        snprintf(buf, (size_t)buflen, "pid %d", pid);
    }
}

/* Renders the bound local address, using "*" for the wildcard address. */
static void fill_address(int32_t family, const struct in_sockinfo *ini,
                         char *out, int32_t outlen)
{
    out[0] = '\0';

    if (family == AF_INET) {
        struct in_addr a = ini->insi_laddr.ina_46.i46a_addr4;
        if (a.s_addr == INADDR_ANY) {
            snprintf(out, (size_t)outlen, "*");
            return;
        }
        inet_ntop(AF_INET, &a, out, (socklen_t)outlen);
    } else if (family == AF_INET6) {
        static const struct in6_addr zero = IN6ADDR_ANY_INIT;
        struct in6_addr a = ini->insi_laddr.ina_6;
        if (memcmp(&a, &zero, sizeof(a)) == 0) {
            snprintf(out, (size_t)outlen, "*");
            return;
        }
        inet_ntop(AF_INET6, &a, out, (socklen_t)outlen);
    }

    if (out[0] == '\0') {
        snprintf(out, (size_t)outlen, "*");
    }
}

int32_t cps_list_sockets(cps_socket_t *out, int32_t max)
{
    int hint = proc_listallpids(NULL, 0);
    if (hint <= 0) {
        return -1;
    }

    int cap = hint + 64;
    pid_t *pids = calloc((size_t)cap, sizeof(pid_t));
    if (pids == NULL) {
        return -1;
    }

    int pid_count = proc_listallpids(pids, cap * (int)sizeof(pid_t));
    if (pid_count <= 0) {
        free(pids);
        return 0;
    }

    int32_t count = 0;

    for (int i = 0; i < pid_count; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) {
            continue;
        }

        int fdb = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
        if (fdb <= 0) {
            continue;
        }

        int fdcap = fdb / (int)sizeof(struct proc_fdinfo) + 8;
        struct proc_fdinfo *fds = calloc((size_t)fdcap, sizeof(struct proc_fdinfo));
        if (fds == NULL) {
            continue;
        }

        int fdu = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds,
                               fdcap * (int)sizeof(struct proc_fdinfo));
        int fdn = fdu / (int)sizeof(struct proc_fdinfo);

        /* Resolve the owning uid once per process. */
        int32_t uid = 0;
        struct proc_bsdinfo bsd;
        if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) == (int)sizeof(bsd)) {
            uid = (int32_t)bsd.pbi_uid;
        }

        for (int j = 0; j < fdn; j++) {
            if (fds[j].proc_fdtype != PROX_FDTYPE_SOCKET) {
                continue;
            }

            struct socket_fdinfo info;
            int r = proc_pidfdinfo(pid, fds[j].proc_fd, PROC_PIDFDSOCKETINFO,
                                   &info, sizeof(info));
            if (r != (int)sizeof(info)) {
                continue;
            }

            int family = info.psi.soi_family;
            int proto = info.psi.soi_protocol;
            if (family != AF_INET && family != AF_INET6) {
                continue;
            }
            if (proto != IPPROTO_TCP && proto != IPPROTO_UDP) {
                continue;
            }

            /* tcpsi_ini is the first member of tcp_sockinfo, so this is the
               in_sockinfo for both TCP and UDP sockets. */
            const struct in_sockinfo *ini = &info.psi.soi_proto.pri_tcp.tcpsi_ini;
            uint16_t port = ntohs((uint16_t)(ini->insi_lport & 0xFFFF));
            int tcp_state = info.psi.soi_proto.pri_tcp.tcpsi_state;

            /* Keep TCP listeners only, and drop unbound (port 0) sockets. */
            if (proto == IPPROTO_TCP && tcp_state != TCPS_LISTEN) {
                continue;
            }
            if (port == 0) {
                continue;
            }

            if (out != NULL && count < max) {
                cps_socket_t *s = &out[count];
                memset(s, 0, sizeof(*s));
                s->pid = pid;
                s->uid = uid;
                s->fd = fds[j].proc_fd;
                s->family = family;
                s->protocol = proto;
                s->state = (proto == IPPROTO_TCP) ? tcp_state : 0;
                s->port = port;
                fill_address(family, ini, s->address, (int32_t)sizeof(s->address));
                fill_name(pid, s->name, (int32_t)sizeof(s->name));
            }
            count++;
        }

        free(fds);
    }

    free(pids);
    return count;
}
