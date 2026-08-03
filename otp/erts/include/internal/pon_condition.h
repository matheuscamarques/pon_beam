/*
 * pon_condition.h — Condition PON-BEAM
 *
 * Uma Condition (Condio) no PON a conjuno de Premises:
 * quando todas as Premises de um processo vo satisfeitas,
 * a Condition notifica o scheduler que h trabalho disponvel.
 *
 * Na PON-BEAM, a Condition substitue a run queue passiva
 * por um mecanismo de notificao: em vez de polling, o
 * scheduler bloqueia no eventfd at que uma Condition notifique.
 *
 * S compilado quando PON_BEAM est definido.
 * Compila de forma independente (apenas POSIX + stdint).
 */

#ifndef PON_CONDITION_H__
#define PON_CONDITION_H__

#ifdef PON_BEAM

#include <stdint.h>

/*
 * Nmero mximo de processes por lote de notificao.
 */
#define PON_CONDITION_BATCH_SIZE 64

/*
 * Estrutura de uma Condition.
 *
 * Cada scheduler pode ter sua prpria Condition.
 * Processos so adicionados ready_list quando vm prontos,
 * e o scheduler acordado via eventfd.
 */
typedef struct {
    /* eventfd: notificao kernel-level para acordar scheduler */
    int          wake_fd;

    /* File descriptors para epoll (timerfds, etc.) */
    int          epoll_fd;

    /* Estado: 1 se h trabalho disponvel */
    int          satisfied;

    /* Lista lock-free de processos prontos */
    void        *ready_list;
    void        *ready_list_tail;

    /* Contadores de eventos (monotnicos) */
    uint64_t     wakeup_count;
    uint64_t     notify_count;
} ErtsCondition;

/*
 * Cria uma nova Condition com eventfd + epoll.
 * Retorna 0 em sucesso, -1 em erro.
 */
int  pon_condition_create(ErtsCondition *cond);

/*
 * Destri uma Condition.
 */
void pon_condition_destroy(ErtsCondition *cond);

/*
 * Notifica a Condition que h um processo pronto.
 * thread-safe, no bloqueante.
 *
 * Se a Condition j estava satisfeita, apenas adiciona
 * o processo ready_list. Se no estava, acorda o scheduler
 * via eventfd.
 */
void pon_condition_notify(ErtsCondition *cond, void *process);

/*
 * Aguarda at que a Condition seja notificada.
 * Bloqueante: a thread dorme at que eventfd seja escrito.
 *
 * Retorna a lista de processos prontos.
 */
void *pon_condition_wait(ErtsCondition *cond);

/*
 * Tentativa no bloqueante de obter processo pronto.
 * Retorna NULL se no houver.
 */
void *pon_condition_try_dequeue(ErtsCondition *cond);

/*
 * Verifica se a Condition est satisfeita (sem bloquear).
 */
int  pon_condition_is_satisfied(ErtsCondition *cond);

/*
 * Retorna o epoll fd da Condition (para registrar timerfds, etc.)
 */
int  pon_condition_get_epoll_fd(ErtsCondition *cond);

#endif /* PON_BEAM */
#endif /* PON_CONDITION_H__ */
