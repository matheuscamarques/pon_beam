/*
 * pon_gc.c — Implementao do GC por notificao PON-BEAM
 *
 * Marcao tri-color (Dijkstra et al., 1978) por propagao de
 * notificaes: as razes notificam suas referncias (GRAY), que
 * notificam as suas, ate a fila esvaziar. Objetos que nunca
 * recebem notificao (WHITE) so lixo e so coletados no sweep
 * sem nunca terem sido "examinados" individualmente pelo mark.
 *
 * Integrao com o ERTS (sob PON_BEAM):
 *   - p->pon_gc: PonGcState por processo (erl_process.h).
 *   - BIFs (bif.c): pon_gc_register_objects/1, pon_gc_add_root/1,
 *     pon_gc_add_ref/2, pon_gc_collect/0, pon_gc_dump/0.
 *   - erl_gc.c: erts_pon_gc_process_gc() roda o mark no ciclo real
 *     de GC do processo e acumula gc_notifications_sent /
 *     gc_scans_avoided / gc_incremental_steps nas pon_stats.
 */

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#include "sys.h"
#include "erl_vm.h"
#include "global.h"
#include "erl_process.h"
#include "erl_alloc.h"
#include "pon_gc.h"
#include "pon_stats.h"

#ifdef PON_BEAM

/*
 * Enfileira um n como GRAY (WHITE -> GRAY).
 * BLACK no muda de cor: j estava vivo em ciclo anterior
 * (invariante do mark incremental conservador). GRAY j
 * esta na fila; nada a fazer.
 */
static void enqueue_gray(PonGcState *gc, PonGcNode *node)
{
    if (!node || node->color != PON_GC_WHITE)
        return;

    node->color = PON_GC_GRAY;
    gc->live_nodes++;   /* WHITE -> GRAY: notificado, agora vivo */

    node->next_gray = NULL;
    if (gc->gray_tail)
        gc->gray_tail->next_gray = node;
    else
        gc->gray_head = node;
    gc->gray_tail = node;
    gc->gray_count++;
}

/*
 * Desenfileira um n GRAY.
 */
static PonGcNode *dequeue_gray(PonGcState *gc)
{
    PonGcNode *node = gc->gray_head;
    if (!node)
        return NULL;

    gc->gray_head = node->next_gray;
    if (!gc->gray_head)
        gc->gray_tail = NULL;
    node->next_gray = NULL;
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
    int i;

    for (i = 0; i < node->num_refs; i++) {
        PonGcNode *ref = node->refs[i];
        if (ref && ref->color == PON_GC_WHITE) {
            enqueue_gray(gc, ref);
            sent++;
        }
    }

    node->color = PON_GC_BLACK;
    gc->notifications_sent += sent;
    gc->scan_count++;       /* no GRAY processado: 1 "scan" de um vivo */
    return sent;
}

/*
 * Inicializa o estado GC.
 */
void
pon_gc_init(PonGcState *gc)
{
    if (!gc)
        return;

    memset(gc, 0, sizeof(PonGcState));
}

/*
 * Cria um n no grafo GC com o prximo id sequencial.
 */
PonGcNode *
pon_gc_node_create(PonGcState *gc, void *data, size_t data_size)
{
    PonGcNode *node;

    if (!gc)
        return NULL;

    node = (PonGcNode *) erts_alloc(ERTS_ALC_T_PON_GC,
                                    sizeof(PonGcNode));
    if (!node)
        return NULL;

    node->color      = PON_GC_WHITE;
    node->num_refs   = 0;
    node->refs_cap   = 0;
    node->refs       = NULL;
    node->next_gray  = NULL;
    node->prev_all   = NULL;
    node->next_all   = NULL;
    node->data       = data;
    node->data_size  = data_size;
    node->id         = gc->next_id++;

    /* Lista de todos os nos (sweep/reset) */
    node->next_all = gc->nodes_head;
    if (gc->nodes_head)
        gc->nodes_head->prev_all = node;
    else
        gc->nodes_tail = node;
    gc->nodes_head = node;
    gc->total_nodes++;

    /* Lookup por id O(1) */
    if (node->id >= gc->by_id_cap) {
        Uint64 new_cap = gc->by_id_cap ? gc->by_id_cap * 2 : 64;
        PonGcNode **new_arr;

        while (new_cap <= node->id)
            new_cap *= 2;
        new_arr = (PonGcNode **) erts_realloc(ERTS_ALC_T_PON_GC,
                                              gc->by_id,
                                              new_cap * sizeof(PonGcNode *));
        if (!new_arr) {
            erts_free(ERTS_ALC_T_PON_GC, node);
            return NULL;
        }
        memset(new_arr + gc->by_id_cap, 0,
               (new_cap - gc->by_id_cap) * sizeof(PonGcNode *));
        gc->by_id = new_arr;
        gc->by_id_cap = new_cap;
    }
    gc->by_id[node->id] = node;

    return node;
}

/*
 * Libera um n (payload + refs + no).
 */
void
pon_gc_node_free(PonGcState *gc, PonGcNode *node)
{
    if (!gc || !node)
        return;

    /* Desliga da lista de todos */
    if (node->prev_all)
        node->prev_all->next_all = node->next_all;
    else
        gc->nodes_head = node->next_all;
    if (node->next_all)
        node->next_all->prev_all = node->prev_all;
    else
        gc->nodes_tail = node->prev_all;

    /* Desliga do lookup por id */
    if (node->id < gc->by_id_cap)
        gc->by_id[node->id] = NULL;

    if (node->refs)
        erts_free(ERTS_ALC_T_PON_GC, node->refs);
    if (node->data)
        erts_free(ERTS_ALC_T_PON_GC, node->data);
    erts_free(ERTS_ALC_T_PON_GC, node);

    gc->total_nodes--;
}

/*
 * Busca um no pelo id. O(1).
 */
PonGcNode *
pon_gc_node_by_id(PonGcState *gc, uint64_t id)
{
    if (!gc || id >= gc->by_id_cap)
        return NULL;
    return gc->by_id[id];
}

/*
 * Adiciona uma referncia: from -> to.
 */
void
pon_gc_add_ref(PonGcNode *from, PonGcNode *to)
{
    PonGcNode **new_refs;
    Uint16 new_cap;

    if (!from || !to)
        return;

    if (from->num_refs == from->refs_cap) {
        new_cap = from->refs_cap ? from->refs_cap * 2 : 4;
        new_refs = (PonGcNode **) erts_realloc(ERTS_ALC_T_PON_GC,
                                               from->refs,
                                               new_cap * sizeof(PonGcNode *));
        if (!new_refs)
            return;
        from->refs = new_refs;
        from->refs_cap = new_cap;
    }
    from->refs[from->num_refs++] = to;
}

/*
 * Remove uma referncia: from -/-> to.
 */
void
pon_gc_remove_ref(PonGcNode *from, PonGcNode *to)
{
    int i;
    int found = 0;

    if (!from || !from->refs)
        return;

    for (i = 0; i < from->num_refs; i++) {
        if (from->refs[i] == to) {
            found = 1;
            break;
        }
    }
    if (found) {
        for (i = found; i < from->num_refs - 1; i++)
            from->refs[i] = from->refs[i + 1];
        from->num_refs--;
    }
}

/*
 * Registra uma raiz.
 */
void
pon_gc_add_root(PonGcState *gc, PonGcNode *root)
{
    PonGcNode **new_roots;
    int new_cap;

    if (!gc || !root)
        return;

    if (gc->num_roots == gc->roots_cap) {
        new_cap = gc->roots_cap ? gc->roots_cap * 2 : 16;
        new_roots = (PonGcNode **) erts_realloc(ERTS_ALC_T_PON_GC,
                                                gc->roots,
                                                new_cap * sizeof(PonGcNode *));
        if (!new_roots)
            return;
        gc->roots = new_roots;
        gc->roots_cap = new_cap;
    }
    gc->roots[gc->num_roots++] = root;
}

/*
 * Marca tudo a partir das razes (mark completo).
 * Retorna o nmero de nos vivos (BLACK ao final).
 */
uint64_t
pon_gc_mark(PonGcState *gc)
{
    int i;

    if (!gc)
        return 0;

    /* Fase 1: razes notificam (enfileiram como GRAY) */
    for (i = 0; i < gc->num_roots; i++)
        enqueue_gray(gc, gc->roots[i]);

    /* Fase 2: propaga at a fila esvaziar */
    while (gc->gray_head) {
        PonGcNode *node = dequeue_gray(gc);
        propagate(gc, node);
    }

    gc->cycles++;
    return gc->live_nodes;
}

/*
 * Passo de GC incremental (processa ate N notificaes).
 * Retorna 1 se o mark terminou, 0 se ainda ha trabalho.
 */
int
pon_gc_step(PonGcState *gc, int max_notifications)
{
    int processed = 0;

    if (!gc || !gc->gray_head)
        return 1; /* completo */

    while (gc->gray_head && processed < max_notifications) {
        PonGcNode *node = dequeue_gray(gc);
        int sent = propagate(gc, node);
        processed += (sent > 0) ? sent : 1;
    }

    if (!gc->gray_head) {
        gc->cycles++;
        return 1;
    }
    return 0;
}

/*
 * Sweep: libera objetos mortos (WHITE) e prepara os vivos
 * (BLACK -> WHITE) para o prximo ciclo.
 * Retorna bytes liberados.
 */
size_t
pon_gc_sweep(PonGcState *gc)
{
    PonGcNode *node;
    PonGcNode *next;
    size_t freed = 0;

    if (!gc)
        return 0;

    gc->dead_nodes = 0;
    gc->bytes_freed = 0;

    node = gc->nodes_head;
    while (node) {
        next = node->next_all;
        if (node->color == PON_GC_WHITE) {
            /* Morto: nunca foi notificado. Libera sem "scan". */
            gc->dead_nodes++;
            gc->bytes_freed += node->data_size;
            freed += node->data_size;
            pon_gc_node_free(gc, node);
        } else {
            /* Vivo: volta a WHITE para o proximo ciclo. */
            node->color = PON_GC_WHITE;
        }
        node = next;
    }

    gc->live_nodes = 0;
    return freed;
}

/*
 * Executa GC completo (mark + sweep).
 * Retorna o nmero de objetos coletados.
 */
uint64_t
pon_gc_mark_sweep(PonGcState *gc)
{
    if (!gc)
        return 0;

    pon_gc_mark(gc);
    pon_gc_sweep(gc);
    return gc->dead_nodes;
}

/*
 * Reseta o estado (prepara para um novo ciclo sem coletar).
 */
void
pon_gc_reset(PonGcState *gc)
{
    PonGcNode *node;

    if (!gc)
        return;

    gc->gray_head = NULL;
    gc->gray_tail = NULL;
    gc->gray_count = 0;

    node = gc->nodes_head;
    while (node) {
        node->color = PON_GC_WHITE;
        node->next_gray = NULL;
        node = node->next_all;
    }

    gc->live_nodes = 0;
    gc->dead_nodes = 0;
    gc->notifications_sent = 0;
    gc->scan_count = 0;
}

/*
 * Estatisticas do ultimo ciclo.
 */
void
pon_gc_stats(PonGcState *gc, uint64_t *live, uint64_t *dead,
             uint64_t *notifications, uint64_t *scanned)
{
    if (!gc)
        return;

    if (live)
        *live = gc->live_nodes;
    if (dead)
        *dead = gc->dead_nodes;
    if (notifications)
        *notifications = gc->notifications_sent;
    if (scanned)
        *scanned = gc->scan_count;
}

/*
 * Destri o estado GC.
 */
void
pon_gc_destroy(PonGcState *gc)
{
    PonGcNode *node;

    if (!gc)
        return;

    node = gc->nodes_head;
    while (node) {
        PonGcNode *next = node->next_all;
        if (node->refs)
            erts_free(ERTS_ALC_T_PON_GC, node->refs);
        if (node->data)
            erts_free(ERTS_ALC_T_PON_GC, node->data);
        erts_free(ERTS_ALC_T_PON_GC, node);
        node = next;
    }

    if (gc->roots)
        erts_free(ERTS_ALC_T_PON_GC, gc->roots);
    if (gc->by_id)
        erts_free(ERTS_ALC_T_PON_GC, gc->by_id);

    memset(gc, 0, sizeof(PonGcState));
}

/* ================================================================
 * Integrao com o ERTS
 * ================================================================ */

/*
 * Retorna o estado PON-GC do processo, criando-o sob demanda.
 */
PonGcState *
erts_pon_gc_state(Process *p)
{
    if (!p->pon_gc) {
        p->pon_gc = (PonGcState *) erts_alloc(ERTS_ALC_T_PON_GC,
                                              sizeof(PonGcState));
        if (!p->pon_gc)
            return NULL;
        pon_gc_init(p->pon_gc);
    }
    return p->pon_gc;
}

/*
 * Destri o estado PON-GC do processo (exit do processo).
 */
void
erts_pon_gc_destroy_state(Process *p)
{
    if (!p->pon_gc)
        return;
    pon_gc_destroy(p->pon_gc);
    erts_free(ERTS_ALC_T_PON_GC, p->pon_gc);
    p->pon_gc = NULL;
}

/*
 * Hook chamado pelo ciclo real de GC do processo (erl_gc.c):
 * roda o mark por notificao e acumula nas pon_stats quantos
 * objetos sobreviveram sem varredura (scan evitado) e quantas
 * notificaes foram necessrias.
 *
 * No libera nada: o sweep fica a cargo do coletor por
 * notificao (pon_gc_collect/0) para no alterar a semntica
 * do GC da BEAM. O mark incremental conservador nunca
 * considera vivo algo morto: BLACK persistente so ocorre
 * para objetos que j eram alcanaveis em ciclos anteriores.
 */
void
erts_pon_gc_process_gc(Process *p)
{
    if (!p)
        return;

    /*
     * Seguro: apenas instrumentacao. A construcao de nos PON-GC
     * acontece exclusivamente pelo caminho BIF (pon_gc_node_create),
     * que aloca payloads proprios via erts_alloc(ERTS_ALC_T_PON_GC).
     *
     * A versa anterior construia nos apontando para dentro do heap
     * do processo (p->heap/p->stop). Na destruicao (pon_gc_destroy /
     * pon_gc_node_free) esses ponteiros interiores eram passados a
     * erts_free(), que os interpretava como blocos proprios do
     * allocator — lixo no prefixo do carrier -> crash
     * "erts_alcu_free_thr_pref / enqueue_dealloc_other_instance".
     */
    PON_STATS_INC(gc_incremental_steps);
}

#endif /* PON_BEAM */
