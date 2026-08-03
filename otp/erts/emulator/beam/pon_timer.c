/*
 * pon_timer.c — Timerfd wrapper para PON-BEAM
 *
 * Gerenciamento de timerfd (Linux) sem dependncia direta de
 * headers internos do OTP. Usa apenas POSIX + pon_instigation.h.
 *
 * A integrao com processos OTP (envio de mensagens na expirao)
 * ser feita na Fase 4 (PON-Scheduler).
 *
 * Compila com: gcc -c -DPON_BEAM -std=c99 pon_timer.c
 */

#ifdef PON_BEAM

#include "pon_instigation.h"
#include "pon_stats.h"

#include <sys/timerfd.h>
#include <sys/epoll.h>
#include <unistd.h>
#include <stdint.h>
#include <stdlib.h>

#define PON_TIMER_MIN_MS     1
#define PON_TIMER_MAX_EVENTS 64

static int pon_timer_epoll_fd = -1;

void pon_timer_init(void)
{
    if (pon_timer_epoll_fd == -1)
        pon_timer_epoll_fd = epoll_create1(0);
}

void pon_timer_destroy(void)
{
    if (pon_timer_epoll_fd != -1) {
        close(pon_timer_epoll_fd);
        pon_timer_epoll_fd = -1;
    }
}

int pon_timer_instigation_create(ErtsTimerInstigation *inst)
{
    int tfd;
    struct itimerspec spec;
    struct epoll_event ev;
    uint64_t timeout_ms;

    if (!inst) return -1;
    timeout_ms = inst->expiration_ms;
    if (timeout_ms < PON_TIMER_MIN_MS)
        return -1;

    tfd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK);
    if (tfd == -1) return -1;

    spec.it_interval.tv_sec  = 0;
    spec.it_interval.tv_nsec = 0;
    spec.it_value.tv_sec     = (long)(timeout_ms / 1000);
    spec.it_value.tv_nsec    = (long)((timeout_ms % 1000) * 1000000ULL);

    if (timerfd_settime(tfd, 0, &spec, NULL) == -1) {
        close(tfd);
        return -1;
    }

    if (pon_timer_epoll_fd != -1) {
        ev.events   = EPOLLIN;
        ev.data.ptr = (void *)inst;
        if (epoll_ctl(pon_timer_epoll_fd, EPOLL_CTL_ADD, tfd, &ev) == -1) {
            close(tfd);
            return -1;
        }
    }

    inst->timer_fd = tfd;
    return 0;
}

void pon_timer_instigation_cancel(ErtsTimerInstigation *inst)
{
    if (!inst || inst->timer_fd == -1) return;

    if (pon_timer_epoll_fd != -1)
        epoll_ctl(pon_timer_epoll_fd, EPOLL_CTL_DEL, inst->timer_fd, NULL);

    close(inst->timer_fd);
    inst->timer_fd = -1;
    inst->base.fired = 1;
}

void pon_timer_instigation_fire(ErtsTimerInstigation *inst)
{
    uint64_t expirations;

    if (!inst || inst->base.fired) return;
    if (inst->timer_fd == -1) return;

    if (read(inst->timer_fd, &expirations, sizeof(expirations)) <= 0)
        return;

    inst->base.fired = 1;
}

int pon_timer_process_expirations(void)
{
    struct epoll_event events[PON_TIMER_MAX_EVENTS];
    int nfds = 0, processed = 0;

    if (pon_timer_epoll_fd == -1) return 0;

    nfds = epoll_wait(pon_timer_epoll_fd, events,
                      PON_TIMER_MAX_EVENTS, 0);
    if (nfds <= 0) return 0;

    for (int i = 0; i < nfds; i++) {
        if (events[i].events & EPOLLIN) {
            ErtsTimerInstigation *inst =
                (ErtsTimerInstigation *)events[i].data.ptr;
            if (inst) {
                pon_timer_instigation_fire(inst);
                processed++;
            }
        }
    }
    return processed;
}

#endif /* PON_BEAM */
