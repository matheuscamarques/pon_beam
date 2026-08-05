/*
 * pon_stats.h — Contadores de instrumentação PON-BEAM
 *
 * Contadores thread-local (per-scheduler) para validação do comportamento
 * dos subsistemas PON. Sempre ativos quando PON_BEAM está definido —
 * `erlang:system_info(pon_stats)` expõe os valores como um mapa.
 *
 * Uso:
 *   PON_STATS_INC(premise_notifications);
 *   PON_STATS_ADD(mailbox_scans_avoided, 42);
 *
 * Sem PON_BEAM, todas as macros são vazias (custo zero).
 */

#ifndef PON_STATS_H__
#define PON_STATS_H__

#ifdef PON_BEAM

#include "sys.h"
#include "erl_term.h"

/* Estrutura de contadores — um por scheduler (thread-local) */
typedef struct {
    /* === PON-Receive === */
    Uint64 premises_registered;      /* Premises registradas */
    Uint64 premise_notifications;    /* Premises notificadas na chegada de msg */
    Uint64 mailbox_scans_avoided;    /* Scans lineares evitados */
    Uint64 messages_classified;      /* Mensagens classificadas por tipo */
    Uint64 messages_type_collision;  /* Colises no bucket de tipo */
    Uint64 messages_pon_queued;      /* Mensagens enfileiradas via PON path */

    /* === PON-Timer === */
    Uint64 timerfd_created;          /* timerfd criados */
    Uint64 timerfd_expirations;      /* Expiraes via timerfd */
    Uint64 timer_wheel_fallback;     /* Quedas para timer wheel */
    Uint64 timer_instigations;       /* Instigaes registradas */
    Uint64 timer_scans_avoided;      /* Varreduras find_next_timeout evitadas */

    /* === PON-Scheduler === */
    Uint64 condition_wakeups;        /* Vezes que eventfd acordou scheduler */
    Uint64 condition_notifications;  /* Notificaes para Condition */
    Uint64 scheduler_idle_blocks;    /* Vezes que scheduler bloqueou no eventfd */

    /* === PON-ETS === */
    Uint64 ets_watchers_registered;  /* Watchers registrados */
    Uint64 ets_watcher_hits;         /* Lookups evitados por notificao */

    /* === PON-GC === */
    Uint64 gc_notifications_sent;    /* Notificaes de marcao enviadas */
    Uint64 gc_scans_avoided;         /* Varreduras de raiz evitadas */
    Uint64 gc_incremental_steps;     /* Passos de GC incremental */

    /* === Temporais === */
    Uint64 pon_overhead_us;          /* Microssegundos gastos em infra PON */
} PonStats;

/* Ponteiro thread-local para stats per-scheduler.
 * A instância é definida em erl_process.c. */
extern __thread PonStats pon_stats;

/* Atalhos para incremento */
#define PON_STATS_INC(field)           (pon_stats.field++)
#define PON_STATS_ADD(field, n)        (pon_stats.field += (n))

/* Marca tempo de início/fim para medir overhead (ms) */
#define PON_STATS_BEGIN_TIMER()        Uint64 __pon_start = erts_timestamp_millis()
#define PON_STATS_END_TIMER()          PON_STATS_ADD(pon_overhead_us, (erts_timestamp_millis() - __pon_start) * 1000)

#endif /* PON_BEAM */
#endif /* PON_STATS_H__ */
