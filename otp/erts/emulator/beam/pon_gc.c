/*
 * pon_gc.c — GC por notificao PON-BEAM
 *
 * Implementa o algoritmo de marcao tri-color (Dijkstra, 1978)
 * usando propagaode notificaes em vez de varredura de razes.
 *
 * Compilao standalone:
 *   gcc -DPON_BEAM -D_GNU_SOURCE -std=c99 -c pon_gc.c
 */

#ifdef PON_BEAM

#include "pon_gc.h"
#include "pon_stats.h"
#include <stdlib.h>
#include <string.h>

/*
 * Inicializa o estado GC.
 */
void pon_gc_init(PonGcState *gc)
{
    if (!gc) return;
    gc->roots           = NULL;
    gc->num_roots       = 0;
    gc->gray_head       = NULL;
    gc->gray_tail       = NULL;
    gc->gray_count      = 0;
    gc->total_nodes     = 0;
    gc->live_nodes      = 0;
    gc->dead_nodes      = 0;
    gc->notifications_sent = 0;
    gc->scan_count      = 0;
}

/*
 * Cria um n no grafo GC.
 */
PonGcNode *pon_gc_node_create(PonGcState *gc, void *data, size_t data_size)
{
    PonGcNode *node = (PonGcNode *)calloc(1, sizeof(PonGcNode));
    if (!node) return NULL;

    node->color      = PON_GC_WHITE;
    node->referenced = 0;
    node->num_refs   = 0;
    node->refs       = NULL;
    node->next_gray  = NULL;
    node->data       = data;
    node->data_size  = data_size;

    gc->total_nodes++;
    return node;
}

/*
 * Adiciona uma referncia: from -> to.
 */
void pon_gc_add_ref(PonGcNode *from, PonGcNode *to)
{
    if (!from || !to) return;

    from->num_refs++;
    from->refs = (PonGcNode **)realloc(from->refs,
                                        from->num_refs * sizeof(PonGcNode *));
    if (from->refs)
        from->refs[from->num_refs - 1] = to;
}

/*
 * Remove uma referncia: from -/-> to.
 */
void pon_gc_remove_ref(PonGcNode *from, PonGcNode *to)
{
    if (!from || !from->refs) return;

    int found = 0;
    for (int i = 0; i < from->num_refs; i++) {
        if (from->refs[i] == to) {
            found = 1;
        }
        if (found && i + 1 < from->num_refs)
            from->refs[i] = from->refs[i + 1];
    }
    if (found) {
        from->num_refs--;
        from->refs = (PonGcNode **)realloc(from->refs,
                                            from->num_refs * sizeof(PonGcNode *));
    }
}

/*
 * Registra uma raz.
 */
void pon_gc_add_root(PonGcState *gc, PonGcNode *root)
{
    if (!gc || !root) return;

    gc->roots = (PonGcNode **)realloc(gc->roots,
                                       (gc->num_roots + 1) * sizeof(PonGcNode *));
    if (gc->roots)
        gc->roots[gc->num_roots++] = root;
}

/*
 * Enfileira um n como GRAY para processamento.
 */
static void enqueue_gray(PonGcState *gc, PonGcNode *node)
{
    if (!node || node->color == PON_GC_BLACK) return;

    if (node->color != PON_GC_GRAY) {
        node->color = PON_GC_GRAY;
        node->next_gray = NULL;

        if (gc->gray_tail)
            gc->gray_tail->next_gray = node;
        else
            gc->gray_head = node;

        gc->gray_tail = node;
        gc->gray_count++;
    }
}

/*
 * Desenfileira um n GRAY.
 */
static PonGcNode *dequeue_gray(PonGcState *gc)
{
    if (!gc->gray_head) return NULL;

    PonGcNode *node = gc->gray_head;
    gc->gray_head = node->next_gray;
    if (!gc->gray_head)
        gc->gray_tail = NULL;

    gc->gray_count--;
    return node;
}

/*
 * Propaga notificao de um n GRAY para suas referncias.
 * Retorna o nmero de notificaes enviadas.
 */
static int propagate(PonGcState *gc, PonGcNode *node)
{
    int sent = 0;

    for (int i = 0; i < node->num_refs; i++) {
        PonGcNode *ref = node->refs[i];
        if (ref && ref->color != PON_GC_BLACK) {
            enqueue_gray(gc, ref);
            sent++;
        }
    }

    node->color = PON_GC_BLACK;
    gc->notifications_sent += sent;
    return sent;
}

/*
 * Executa GC completo (marca tudo at a fila GRAY esvaziar).
 */
int pon_gc_mark_sweep(PonGcState *gc)
{
    if (!gc) return 0;

    /* Fase 1: razes como GRAY */
    for (int i = 0; i < gc->num_roots; i++) {
        enqueue_gray(gc, gc->roots[i]);
    }

    /* Fase 2: propaga at esvaziar */
    while (gc->gray_head) {
        PonGcNode *node = dequeue_gray(gc);
        propagate(gc, node);

        gc->scan_count++;
        PON_STATS_INC(gc_notifications_sent);
    }

    /* Fase 3: coleta WHITE */
    int collected = 0;
    for (int i = 0; i < gc->total_nodes; i++) {
        /* NOTA: preciso percorrer todos os ns.
           Numa implementao real, os ns esto no heap
           e podemos iterar sobre o heap. */
    }

    PON_STATS_ADD(gc_notifications_sent, gc->notifications_sent);
    PON_STATS_ADD(gc_scans_avoided, gc->total_nodes - gc->scan_count);

    return collected;
}

/*
 * Passo de GC incremental (processa N notificaes).
 */
int pon_gc_step(PonGcState *gc, int max_notifications)
{
    if (!gc || !gc->gray_head) return 1; /* completo */

    int processed = 0;

    while (gc->gray_head && processed < max_notifications) {
        PonGcNode *node = dequeue_gray(gc);
        int sent = propagate(gc, node);
        processed += sent;
        gc->scan_count++;
        PON_STATS_INC(gc_notifications_sent);
    }

    /* Se fila vazia, GC completo */
    if (!gc->gray_head) {
        int collected = 0;
        /* Coleta WHITE */
        return 1;
    }

    return 0; /* ainda h trabalho */
}

/*
 * Libera objetos mortos (WHITE).
 * Numa implementao real, percorre o heap.
 */
size_t pon_gc_sweep(PonGcState *gc)
{
    if (!gc) return 0;

    size_t freed = 0;
    gc->dead_nodes = 0;
    gc->live_nodes = 0;

    /* Simula sweep: conta vivos e mortos */
    for (int i = 0; i < gc->num_roots; i++) {
        /* Percorrer grafo a partir das razes */
        (void)i;
    }

    return freed;
}

/*
 * Reseta o estado para novo ciclo.
 */
void pon_gc_reset(PonGcState *gc)
{
    if (!gc) return;

    gc->gray_head       = NULL;
    gc->gray_tail       = NULL;
    gc->gray_count      = 0;
    gc->notifications_sent = 0;
    gc->scan_count      = 0;

    /* Reseta cores dos ns */
    for (int i = 0; i < gc->total_nodes; i++) {
        /* Numa implementao real, iteramos sobre o heap */
    }
}

/*
 * Destri o estado.
 */
void pon_gc_destroy(PonGcState *gc)
{
    if (!gc) return;

    free(gc->roots);
    gc->roots     = NULL;
    gc->num_roots = 0;
}

#endif /* PON_BEAM */
