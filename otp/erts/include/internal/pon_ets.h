/*
 * pon_ets.h — Watchers PON-BEAM para ETS
 *
 * Registro lateral de watchers: processos podem registrar interesse
 * em chaves de tabelas ETS e ser notificados quando a chave muda,
 * eliminando a necessidade de polling (ets:lookup repetido).
 *
 * O registro de watchers mantido separado das estruturas internas
 * do ETS (DbTable), usando um hash map prprio.
 */

#ifndef PON_ETS_H__
#define PON_ETS_H__

#ifdef PON_BEAM

#include <stdint.h>

/*
 * Nmero de buckets do hash de watchers.
 * Quanto maior, menos colises.
 */
#define PON_ETS_WATCHER_BUCKETS 1024

/*
 * Um watcher associa (table_id, key_hash) a um processo.
 */
typedef struct PonEtsWatcher_ {
    uint64_t              table_id;       /* Identificador da tabela ETS */
    uint64_t              key_hash;        /* Hash da chave observada */
    uint64_t              process_id;      /* PID do processo watcher (como uint64) */
    struct PonEtsWatcher_ *next;           /* Lista ligada (colises) */
    int                   active;          /* 1 se ativo, 0 se cancelado */
} PonEtsWatcher;

/*
 * Registro de watchers: array de buckets com listas ligadas.
 */
typedef struct {
    PonEtsWatcher *buckets[PON_ETS_WATCHER_BUCKETS];
    int            count;                  /* Total de watchers ativos */
} PonEtsWatcherRegistry;

/*
 * Inicializa o registro global de watchers.
 */
void pon_ets_watcher_init(PonEtsWatcherRegistry *reg);

/*
 * Registra um watcher.
 * Retorna 0 em sucesso, -1 se j existe.
 */
int pon_ets_watcher_add(PonEtsWatcherRegistry *reg,
                        uint64_t table_id, uint64_t key_hash,
                        uint64_t process_id);

/*
 * Remove um watcher.
 * Retorna 0 se encontrado e removido, -1 se no existia.
 */
int pon_ets_watcher_remove(PonEtsWatcherRegistry *reg,
                           uint64_t table_id, uint64_t key_hash,
                           uint64_t process_id);

/*
 * Notifica todos os watchers de uma chave que ela foi alterada.
 * Retorna o nmero de watchers notificados.
 */
int pon_ets_watcher_notify(PonEtsWatcherRegistry *reg,
                           uint64_t table_id, uint64_t key_hash);

/*
 * Remove todos os watchers de um processo (quando ele morre).
 */
int pon_ets_watcher_remove_process(PonEtsWatcherRegistry *reg,
                                   uint64_t process_id);

/*
 * Calcula o bucket de hash para (table_id, key_hash).
 */
static inline unsigned
pon_ets_watcher_bucket(uint64_t table_id, uint64_t key_hash)
{
    uint64_t h = table_id ^ key_hash;
    h ^= h >> 32;
    h ^= h >> 16;
    h ^= h >> 8;
    return (unsigned)(h % PON_ETS_WATCHER_BUCKETS);
}

#endif /* PON_BEAM */
#endif /* PON_ETS_H__ */
