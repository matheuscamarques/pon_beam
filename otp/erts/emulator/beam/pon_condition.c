/*
 * pon_condition.c — Implementao da Condition PON-BEAM
 *
 * Uma Condition substitue o polling da run queue por notificao:
 * o scheduler bloqueia no eventfd at que um processo seja
 * adicionado ready_list e o eventfd seja escrito.
 *
 * Compilao standalone:
 *   gcc -DPON_BEAM -D_GNU_SOURCE -std=c99 -c pon_condition.c
 */

#ifdef PON_BEAM

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#include "pon_condition.h"
#include "pon_stats.h"

#include <sys/eventfd.h>
#include <sys/epoll.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdatomic.h>

/*
 * Cria uma Condition com eventfd + epoll.
 */
int pon_condition_create(ErtsCondition *cond)
{
    if (!cond) return -1;

    cond->wake_fd = eventfd(0, EFD_NONBLOCK);
    if (cond->wake_fd == -1) return -1;

    cond->epoll_fd = epoll_create1(0);
    if (cond->epoll_fd == -1) {
        close(cond->wake_fd);
        return -1;
    }

    /* Registra o eventfd no epoll para monitorar notificaes */
    struct epoll_event ev;
    ev.events   = EPOLLIN;
    ev.data.fd  = cond->wake_fd;
    if (epoll_ctl(cond->epoll_fd, EPOLL_CTL_ADD, cond->wake_fd, &ev) == -1) {
        close(cond->epoll_fd);
        close(cond->wake_fd);
        return -1;
    }

    cond->satisfied      = 0;
    cond->ready_list     = NULL;
    cond->ready_list_tail = NULL;
    cond->wakeup_count   = 0;
    cond->notify_count   = 0;

    return 0;
}

/*
 * Destri a Condition.
 */
void pon_condition_destroy(ErtsCondition *cond)
{
    if (!cond) return;

    if (cond->epoll_fd != -1) close(cond->epoll_fd);
    if (cond->wake_fd != -1)  close(cond->wake_fd);

    cond->wake_fd   = -1;
    cond->epoll_fd  = -1;
    cond->satisfied = 0;
    cond->ready_list = NULL;
}

/*
 * Notifica a Condition que h um processo pronto.
 *
 * Adiciona o processo ready_list (lock-free via CAS)
 * e, se a Condition estava insatisfeita, escreve no eventfd
 * para acordar o scheduler.
 */
void pon_condition_notify(ErtsCondition *cond, void *process)
{
    if (!cond || !process) return;

    /*
     * Adiciona o processo como um n na ready_list.
     * Usamos o primeiro campo do processo como next pointer.
     * O layout do n : { void *next; ... dados ... }
     */
    void **node = (void **)process;
    void *old_head;

    /* CAS: head = process; process->next = old_head */
    do {
        old_head = (void *)atomic_load_explicit(
            (atomic_uintptr_t *)&cond->ready_list,
            memory_order_acquire);
        *node = old_head;
    } while (!atomic_compare_exchange_weak_explicit(
        (atomic_uintptr_t *)&cond->ready_list,
        (uintptr_t *)&old_head,
        (uintptr_t)process,
        memory_order_release,
        memory_order_acquire));

    cond->notify_count++;

    /* Se a Condition estava insatisfeita, acorda o scheduler */
    if (!cond->satisfied) {
        cond->satisfied = 1;
        uint64_t one = 1;
        if (write(cond->wake_fd, &one, sizeof(one)) < 0) {
            /* EAGAIN  ok (j havia notificao pendente) */
        }
    }
}

/*
 * Aguarda at que a Condition seja notificada.
 * Bloqueia no epoll_wait at que o eventfd seja escrito.
 *
 * Retorna a ready_list inteira (ltima cabea antes do reset).
 */
void *pon_condition_wait(ErtsCondition *cond)
{
    if (!cond) return NULL;

    struct epoll_event events[PON_CONDITION_BATCH_SIZE];

    while (1) {
        /*
         * Tenta obter da ready_list primeiro (pode ter notificao
         * pendente do ltimo ciclo).
         */
        void *head = (void *)atomic_load_explicit(
            (atomic_uintptr_t *)&cond->ready_list,
            memory_order_acquire);

        if (head) {
            /*
             * Tenta resetar a ready_list para NULL.
             * Se outro thread adicionou entre nossa leitura e o CAS,
             * o CAS falha e tentamos de novo.
             */
            if (atomic_compare_exchange_strong_explicit(
                (atomic_uintptr_t *)&cond->ready_list,
                (uintptr_t *)&head,
                (uintptr_t)NULL,
                memory_order_acquire,
                memory_order_acquire))
            {
                /* Sucesso: consumimos a lista */
                cond->satisfied = 0;
                cond->wakeup_count++;

                /*
                 * Se houveram notificaes durante a troca,
                 * o eventfd ainda tem dados para ler.
                 * Consumimos para no acumular.
                 */
                uint64_t val;
                while (read(cond->wake_fd, &val, sizeof(val)) > 0) { }

                return head;
            }
            /* CAS falhou (outro thread notificou)  tenta de novo */
            continue;
        }

        /*
         * Ready_list vazia e Condition satisfeita?
         * Pode ser notificao perdida — verifica eventfd.
         */
        if (cond->satisfied) {
            uint64_t val;
            if (read(cond->wake_fd, &val, sizeof(val)) > 0) {
                cond->satisfied = 0;
                continue; /* volta a tentar a ready_list */
            }
            cond->satisfied = 0;
        }

        /*
         * Ready_list vazia, eventfd vazio: bloqueia no epoll
         * at que uma notificao chegue.
         */
        int nfds = epoll_wait(cond->epoll_fd, events,
                              PON_CONDITION_BATCH_SIZE, -1);
        if (nfds > 0) {
            cond->satisfied = 1;
            /* loop: volta ao topo para pegar da ready_list */
        }
    }
}

/*
 * Tentativa no bloqueante de obter um processo pronto.
 */
void *pon_condition_try_dequeue(ErtsCondition *cond)
{
    if (!cond) return NULL;

    void *head = (void *)atomic_load_explicit(
        (atomic_uintptr_t *)&cond->ready_list,
        memory_order_acquire);

    if (!head) return NULL;

    /* Tenta consumir a cabea */
    void **node = (void **)head;
    void *next = *node;

    if (atomic_compare_exchange_strong_explicit(
        (atomic_uintptr_t *)&cond->ready_list,
        (uintptr_t *)&head,
        (uintptr_t)next,
        memory_order_acquire,
        memory_order_acquire))
    {
        if (!next) cond->satisfied = 0;
        return head;
    }

    return NULL; /* CAS falhou — outro thread consumiu */
}

/*
 * Verifica se a Condition est satisfeita (sem bloquear).
 */
int pon_condition_is_satisfied(ErtsCondition *cond)
{
    if (!cond) return 0;
    if (cond->satisfied) return 1;

    /* Verifica no  atico se h ready_list */
    void *head = (void *)atomic_load_explicit(
        (atomic_uintptr_t *)&cond->ready_list,
        memory_order_acquire);

    if (head) {
        cond->satisfied = 1;
        return 1;
    }

    return 0;
}

/*
 * Retorna o epoll fd para registrar descritores adicionais.
 */
int pon_condition_get_epoll_fd(ErtsCondition *cond)
{
    return cond ? cond->epoll_fd : -1;
}

#endif /* PON_BEAM */
