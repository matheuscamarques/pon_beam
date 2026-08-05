/*
 * pon_gc.h — GC por notificacao PON-BEAM
 *
 * Substitui a varredura de raizes (scanning) por propagacao
 * de notificacoes: objetos marcados como GRAY notificam suas
 * referencias, que se tornam GRAY por sua vez.
 *
 * Objetos que permanecem WHITE apos a propagacao sao mortos —
 * nunca foram notificados, logo nunca foram "vistos" pelo GC:
 * a coleta e proporcional ao conjunto vivo, nao ao heap total.
 *
 * Cada processo tem um PonGcState (p->pon_gc, sob PON_BEAM).
 * O estado mantem:
 *   - by_id:  array id -> node (ids O(1) para add_ref/roots)
 *   - all:    lista duplamente ligada de TODOS os nos (sweep/reset)
 *   - gray:   fila FIFO de nos GRAY (mark incremental)
 *
 * So compilado quando PON_BEAM esta definido.
 * O nucleo da biblioteca usa apenas stdint/stdlib.
 */

#ifndef PON_GC_H__
#define PON_GC_H__

#ifdef PON_BEAM

#include <stdint.h>
#include <stdlib.h>

/*
 * Cores do GC tri-color (Dijkstra et al., 1978)
 */
#define PON_GC_WHITE 0
#define PON_GC_GRAY  1
#define PON_GC_BLACK 2

/*
 * Tamanho maximo de notify por passo (GC incremental).
 */
#define PON_GC_STEP_NOTIFICATIONS 1000

/*
 * No do grafo de objetos.
 * Cada objeto na memoria e um no com cor e lista de referencias.
 */
typedef struct PonGcNode_ {
    uint8_t                color;           /* WHITE, GRAY, ou BLACK */
    uint8_t                pad0;
    uint16_t               num_refs;        /* nr de referencias */
    uint16_t               refs_cap;        /* capacidade do vetor refs */
    uint16_t               pad1;
    struct PonGcNode_     **refs;           /* vetor de referencias */
    struct PonGcNode_      *next_gray;      /* fila de GRAY (FIFO) */
    struct PonGcNode_      *prev_all;       /* lista de todos os nos */
    struct PonGcNode_      *next_all;
    void                   *data;           /* ponteiro para o objeto real */
    size_t                 data_size;       /* tamanho do objeto */
    uint64_t               id;              /* id do objeto (chave do BIF) */
} PonGcNode;

/*
 * Estado global do GC de um processo.
 */
typedef struct {
    PonGcNode            **roots;           /* raizes do processo */
    int                    num_roots;
    int                    roots_cap;

    PonGcNode             *gray_head;       /* fila de objetos GRAY */
    PonGcNode             *gray_tail;
    int                    gray_count;      /* total na fila GRAY */

    PonGcNode             *nodes_head;      /* lista de todos os nos */
    PonGcNode             *nodes_tail;
    uint64_t               total_nodes;     /* total de nos no grafo */

    PonGcNode            **by_id;           /* id -> no (lookup O(1)) */
    uint64_t               by_id_cap;       /* capacidade do array */
    uint64_t               next_id;         /* proximo id a atribuir */

    uint64_t               live_nodes;      /* nos vivos (BLACK) */
    uint64_t               dead_nodes;      /* nos mortos (WHITE) */
    uint64_t               bytes_freed;     /* bytes liberados no sweep */

    uint64_t               notifications_sent; /* notificacoes enviadas */
    uint64_t               scan_count;         /* nos realmente varridos */
    uint64_t               cycles;             /* ciclos de mark executados */
} PonGcState;

/*
 * Inicializa o estado GC.
 */
void pon_gc_init(PonGcState *gc);

/*
 * Destroi o estado GC (libera nos, refs, raizes e array by_id).
 */
void pon_gc_destroy(PonGcState *gc);

/*
 * Cria um no no grafo GC e atribui o proximo id.
 * Retorna ponteiro para o no.
 */
PonGcNode *pon_gc_node_create(PonGcState *gc, void *data, size_t data_size);

/*
 * Libera um no especifico (e seu payload data).
 */
void pon_gc_node_free(PonGcState *gc, PonGcNode *node);

/*
 * Busca um no pelo id. O(1).
 */
PonGcNode *pon_gc_node_by_id(PonGcState *gc, uint64_t id);

/*
 * Adiciona uma referencia de from para to.
 */
void pon_gc_add_ref(PonGcNode *from, PonGcNode *to);

/*
 * Remove uma referencia.
 */
void pon_gc_remove_ref(PonGcNode *from, PonGcNode *to);

/*
 * Registra uma raiz.
 */
void pon_gc_add_root(PonGcState *gc, PonGcNode *root);

/*
 * Marca tudo a partir das raizes (mark completo).
 * Retorna numero de nos vivos (BLACK).
 */
uint64_t pon_gc_mark(PonGcState *gc);

/*
 * Executa um passo de GC incremental.
 * Processa ate N notificacoes da fila GRAY.
 * Retorna 1 se o mark esta completo, 0 se ainda ha trabalho.
 */
int pon_gc_step(PonGcState *gc, int max_notifications);

/*
 * Sweep: libera objetos mortos (WHITE). Retorna bytes liberados.
 */
size_t pon_gc_sweep(PonGcState *gc);

/*
 * Executa GC completo (mark + sweep).
 * Retorna numero de objetos coletados.
 */
uint64_t pon_gc_mark_sweep(PonGcState *gc);

/*
 * Reseta as cores (prepara para novo ciclo) mantendo o grafo.
 */
void pon_gc_reset(PonGcState *gc);

/*
 * Estatisticas do ultimo ciclo (para o BIF pon_gc_dump).
 */
void pon_gc_stats(PonGcState *gc, uint64_t *live, uint64_t *dead,
                  uint64_t *notifications, uint64_t *scanned);

#endif /* PON_BEAM */
#endif /* PON_GC_H__ */
