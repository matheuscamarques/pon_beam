/*
 * pon_gc.h — GC por notificao PON-BEAM
 *
 * Substitui a varredura de razes (scanning) por propagao
 * de notificaes: objetos marcados como GRAY notificam suas
 * referncias, que se tornam GRAY por sua vez.
 *
 * Objetos que permanecem WHITE aps a propagao so mortos.
 *
 * S compilado quando PON_BEAM est definido.
 * Compila de forma independente (stdint.h + stdlib.h).
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
 * Tamanho mximo de notify por passo (GC incremental).
 */
#define PON_GC_STEP_NOTIFICATIONS 1000

/*
 * No do grafo de objetos.
 * Cada objeto na memria um n com cor e lista de referncias.
 */
typedef struct PonGcNode_ {
    uint8_t                color;           /* WHITE, GRAY, ou BLACK */
    uint8_t                referenced : 1;  /* visitado? */
    uint16_t               num_refs;        /* nr de referncias */
    struct PonGcNode_      **refs;          /* vetor de referncias */
    struct PonGcNode_      *next_gray;      /* fila de GRAY (lock-free) */
    void                   *data;           /* ponteiro para o objeto real */
    size_t                 data_size;       /* tamanho do objeto */
} PonGcNode;

/*
 * Estado global do GC.
 */
typedef struct {
    PonGcNode   **roots;                   /* razes do processo */
    int           num_roots;
    PonGcNode    *gray_head;               /* fila de objetos GRAY */
    PonGcNode    *gray_tail;
    int           gray_count;              /* total na fila GRAY */
    int           total_nodes;             /* total de ns no grafo */
    int           live_nodes;              /* ns vivos (BLACK) */
    int           dead_nodes;              /* ns mortos (WHITE) */
    uint64_t      notifications_sent;      /* contador de notificaes */
    uint64_t      scan_count;              /* nr de scans equivalentes */
} PonGcState;

/*
 * Inicializa o estado GC.
 */
void pon_gc_init(PonGcState *gc);

/*
 * Cria um n no grafo GC.
 * Retorna ponteiro para o n.
 */
PonGcNode *pon_gc_node_create(PonGcState *gc, void *data, size_t data_size);

/*
 * Adiciona uma referncia de from para to.
 */
void pon_gc_add_ref(PonGcNode *from, PonGcNode *to);

/*
 * Remove uma referncia.
 */
void pon_gc_remove_ref(PonGcNode *from, PonGcNode *to);

/*
 * Registra uma raz.
 */
void pon_gc_add_root(PonGcState *gc, PonGcNode *root);

/*
 * Executa GC completo (marca tudo at a fila GRAY esvaziar).
 * Retorna nmero de objetos coletados.
 */
int pon_gc_mark_sweep(PonGcState *gc);

/*
 * Executa um passo de GC incremental.
 * Processa ate N notificaes da fila GRAY.
 * Retorna 1 se GC completo, 0 se ainda h trabalho.
 */
int pon_gc_step(PonGcState *gc, int max_notifications);

/*
 * Libera objetos mortos (WHITE).
 * Retorna nmero de bytes liberados.
 */
size_t pon_gc_sweep(PonGcState *gc);

/*
 * Reseta o estado (prepara para novo ciclo).
 */
void pon_gc_reset(PonGcState *gc);

/*
 * Destri o estado GC.
 */
void pon_gc_destroy(PonGcState *gc);

#endif /* PON_BEAM */
#endif /* PON_GC_H__ */
