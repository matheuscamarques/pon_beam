/*
 * pon_ets.c — Watchers PON-BEAM para ETS
 *
 * Registro lateral de watchers: processos podem observar chaves
 * de tabelas ETS e ser notificados quando so alteradas.
 *
 * Compilao standalone:
 *   gcc -DPON_BEAM -D_GNU_SOURCE -std=c99 -c pon_ets.c
 */

#ifdef PON_BEAM

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#include "pon_ets.h"
#include "pon_stats.h"
#include <stdlib.h>

/*
 * Inicializa o registro de watchers.
 */
void pon_ets_watcher_init(PonEtsWatcherRegistry *reg)
{
    if (!reg) return;
    for (int i = 0; i < PON_ETS_WATCHER_BUCKETS; i++)
        reg->buckets[i] = NULL;
    reg->count = 0;
}

/*
 * Registra um watcher.
 */
int pon_ets_watcher_add(PonEtsWatcherRegistry *reg,
                        uint64_t table_id, uint64_t key_hash,
                        uint64_t process_id)
{
    if (!reg) return -1;

    unsigned bucket = pon_ets_watcher_bucket(table_id, key_hash);

    /* Verifica se j existe */
    PonEtsWatcher *w = reg->buckets[bucket];
    while (w) {
        if (w->table_id == table_id &&
            w->key_hash == key_hash &&
            w->process_id == process_id &&
            w->active) {
            return -1; /* j registrado */
        }
        w = w->next;
    }

    /* Cria novo watcher */
    w = (PonEtsWatcher *)malloc(sizeof(PonEtsWatcher));
    if (!w) return -1;

    w->table_id   = table_id;
    w->key_hash   = key_hash;
    w->process_id = process_id;
    w->active     = 1;
    w->next       = reg->buckets[bucket];
    reg->buckets[bucket] = w;
    reg->count++;

    PON_STATS_INC(ets_watchers_registered);
    return 0;
}

/*
 * Remove um watcher.
 */
int pon_ets_watcher_remove(PonEtsWatcherRegistry *reg,
                           uint64_t table_id, uint64_t key_hash,
                           uint64_t process_id)
{
    if (!reg) return -1;

    unsigned bucket = pon_ets_watcher_bucket(table_id, key_hash);
    PonEtsWatcher *w = reg->buckets[bucket];
    PonEtsWatcher *prev = NULL;

    while (w) {
        if (w->table_id == table_id &&
            w->key_hash == key_hash &&
            w->process_id == process_id &&
            w->active) {

            w->active = 0;
            reg->count--;

            /* Remove da lista */
            if (prev)
                prev->next = w->next;
            else
                reg->buckets[bucket] = w->next;

            free(w);
            return 0;
        }
        prev = w;
        w = w->next;
    }

    return -1; /* no encontrado */
}

/*
 * Notifica todos os watchers de uma chave.
 *
 * Na implementao atual, apenas registra a notificao
 * nos contadores. O envio efetivo de mensagens para os
 * processos watchers requer integrao com o scheduler
 * e a mailbox (Fases 1 + 4), que ser feita na verso
 * completa.
 *
 * Retorna o nmero de watchers notificados.
 */
int pon_ets_watcher_notify(PonEtsWatcherRegistry *reg,
                           uint64_t table_id, uint64_t key_hash)
{
    if (!reg) return 0;

    unsigned bucket = pon_ets_watcher_bucket(table_id, key_hash);
    int notified = 0;

    PonEtsWatcher *w = reg->buckets[bucket];
    while (w) {
        if (w->active &&
            w->table_id == table_id &&
            w->key_hash == key_hash) {

            /*
             * NOTA: Aqui enviaremos uma mensagem para a mailbox
             * do processo watcher. Por enquanto, apenas contamos.
             *
             * Integrao futura:
             *   1. Criar mensagem {ets_change, TableId, Key}
             *   2. Chamar erts_queue_message_pon(watcher, msg)
             */
            notified++;
            PON_STATS_INC(ets_watcher_hits);
        }
        w = w->next;
    }

    return notified;
}

/*
 * Remove todos os watchers de um processo (cleanup na morte).
 */
int pon_ets_watcher_remove_process(PonEtsWatcherRegistry *reg,
                                   uint64_t process_id)
{
    if (!reg) return -1;

    int removed = 0;

    for (int i = 0; i < PON_ETS_WATCHER_BUCKETS; i++) {
        PonEtsWatcher *w = reg->buckets[i];
        PonEtsWatcher *prev = NULL;

        while (w) {
            PonEtsWatcher *next = w->next;

            if (w->process_id == process_id) {
                if (prev)
                    prev->next = next;
                else
                    reg->buckets[i] = next;

                free(w);
                removed++;
            } else {
                prev = w;
            }

            w = next;
        }
    }

    reg->count -= removed;
    return removed;
}

#endif /* PON_BEAM */
