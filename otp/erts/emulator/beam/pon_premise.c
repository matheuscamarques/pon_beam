/*
 * pon_premise.c — Implementao das Premises PON-BEAM
 *
 * Gerncia de Premises: registro, notificao na chegada de mensagens,
 * e recebimento baseado em Premises (em vez de scanning linear).
 */

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#include "sys.h"
#include "erl_vm.h"
#include "global.h"
#include "erl_process.h"
#include "erl_proc_sig_queue.h"
#include "pon_premise.h"
#include "pon_stats.h"

#ifdef PON_BEAM

/*
 * Sequência global de chegada de mensagens para Premises.
 *
 * Ordena mensagens casadas de Premises distintas pela ordem real de
 * chegada na fila: o receive seletivo escolhe a mensagem mais antiga
 * que casa QUALQUER cláusula (semântica do scan linear do OTP), e a
 * ordem das cláusulas só decide qual cláusula casa dentro da mensagem.
 * Um contador global monotônico preserva a ordem por receiver sem
 * exigir campo no Process (evita colisão de edição no struct).
 */
static erts_atomic64_t pon_msg_seq;

Uint64
erts_pon_next_msg_seq(void)
{
    return (Uint64) erts_atomic64_inc_read_nob(&pon_msg_seq);
}

/*
 * Funo de match default: compara um termo contra um padro.
 * Usa pattern matching simplificado (equivalente ao `=:=`).
 * fallback quando no h match_fn especializada.
 */
int
erts_pon_default_match(Eterm pattern, Eterm term)
{
    if (pattern == term)
        return 1;
    if (is_tuple(pattern) && is_tuple(term)) {
        Eterm *ptr_p = tuple_val(pattern);
        Eterm *ptr_t = tuple_val(term);
        int arity_p = arityval(*ptr_p);
        int arity_t = arityval(*ptr_t);
        if (arity_p != arity_t)
            return 0;
        for (int i = 1; i <= arity_p; i++) {
            Eterm pe = ptr_p[i];
            /* THE_NON_VALUE no padrao = wildcard (casa qualquer coisa) */
            if (is_non_value(pe))
                continue;
            if (pe != ptr_t[i])
                return 0;
        }
        return 1;
    }
    return 0;
}

/*
 * Registra uma lista de Premises no processo.
 * Substitui qualquer lista anterior.
 */
void
 erts_pon_register_premises(Process *p, ErtsPremise *premises)
{
    ErtsPremise *old;
    ErtsPremise *next;

    ASSERT(p != NULL);

    /* Libera premises antigas (se houver) */
    old = p->pon_premises;
    while (old) {
        next = old->next_premise;
        erts_free(ERTS_ALC_T_PON_PREMISE, old);
        old = next;
    }

    p->pon_premises = premises;

    PON_STATS_INC(premises_registered);
}

/*
 * Remove todas as Premises registradas no processo.
 */
void
 erts_pon_unregister_premises(Process *p)
{
    ErtsPremise *prem;
    ErtsPremise *next;

    ASSERT(p != NULL);

    prem = p->pon_premises;
    while (prem) {
        next = prem->next_premise;
        erts_free(ERTS_ALC_T_PON_PREMISE, prem);
        prem = next;
    }
    p->pon_premises = NULL;
}

/*
 * Extrai a tag de tipo de um termo mensagem.
 * Para tuplas: usa o primeiro elemento.
 * Para termos simples: usa o prprio termo.
 * Retorna os 8 bits baixos (bucket index).
 */
static Uint
pon_extract_type_tag(Eterm term)
{
    if (is_tuple(term)) {
        Eterm *ptr = tuple_val(term);
        return pon_type_tag(ptr[0]);
    }
    return pon_type_tag(term);
}

/*
 * Insere uma mensagem na fila de tipo (bucket) correspondente.
 *
 * NOTA: nao alteramos msg->next aqui. A mensagem ja e linkada na fila
 * principal pela ERTS (queue_messages -> LINK_MESSAGE). Re-linkar o
 * mesmo erl_mesg numa segunda lista (type_queue) criaria cycles quando
 * a 2a mensagem do bucket chegasse (last->next = msg, com msg ja na
 * fila principal), corrompendo a mailbox. Ficamos apenas com o counter
 * por bucket; a lista em si c a responsabilidade da fila principal.
 */
static void
pon_enqueue_to_type_queue(Process *p, struct erl_mesg *msg, Uint bucket)
{
    ErtsSignalPrivQueues *qs = &p->sig_qs;

    (void) msg;
    qs->type_queue_len[bucket]++;

    PON_STATS_INC(messages_classified);
    if (qs->type_queue_len[bucket] > 1)
        PON_STATS_INC(messages_type_collision);
}

/*
 * Notifica as Premises do processo sobre a chegada de uma mensagem.
 * Retorna o nmero de Premises que matcharam.
 */
int
 erts_pon_notify_premises(Process *p, struct erl_mesg *msg, Eterm term)
{
    Uint bucket;
    ErtsPremise *prem;
    int matched;

    ASSERT(p != NULL);
    ASSERT(msg != NULL);
    ASSERT(is_value(term));

    if (!p->pon_premises)
        return 0;

    /* Sequência de chegada para a ordenação entre Premises */
    msg->pon_seq = erts_pon_next_msg_seq();

    /* Extrai tag de tipo e classifica */
    bucket = pon_extract_type_tag(term);
    pon_enqueue_to_type_queue(p, msg, bucket);

    /* Notifica cada Premise que matcha o termo */
    matched = 0;
    prem = p->pon_premises;
    while (prem) {
        if (!prem->has_match) {
            int match_ok;
            if (prem->match_fn)
                match_ok = prem->match_fn(term);
            else
                match_ok = erts_pon_default_match(prem->pattern, term);

            if (match_ok) {
                prem->has_match = 1;
                prem->matched_term = term;
                prem->matched_msg = msg;
                matched++;
                PON_STATS_INC(premise_notifications);
                PON_STATS_INC(mailbox_scans_avoided);
            }
        }
        prem = prem->next_premise;
    }

    return matched;
}

/*
 * Receive baseado em Premises.
 * Retorna o termo da primeira Premise satisfeita, ou THE_NON_VALUE
 * se nenhuma Premise est satisfeita (processo deve bloquear).
 */
Eterm
 erts_pon_receive(Process *p)
{
    ErtsPremise *best;
    ErtsPremise *prem;
    Eterm result;

    ASSERT(p != NULL);

    if (!p->pon_premises)
        return THE_NON_VALUE;

    /* Procura a primeira Premise satisfeita (pela ordem das clusulas) */
    best = NULL;
    prem = p->pon_premises;
    while (prem) {
        if (prem->has_match) {
            if (!best || prem->clause_index < best->clause_index)
                best = prem;
        }
        prem = prem->next_premise;
    }

    if (!best)
        return THE_NON_VALUE;

    /* Consome a mensagem */
    result = best->matched_term;
    best->has_match = 0;
    best->matched_term = THE_NON_VALUE;
    best->matched_msg = NULL;

    return result;
}

/*
 * Fast-path do selective receive (interpreter).
 *
 * Posiciona o save pointer da fila principal diretamente na mensagem
 * que a Premise notificou. Chamado pelo scan advance — hook em
 * erts_msgq_set_save_next (loop_rec_end) — que roda na PRIMEIRA
 * iteração de cada receive: no estado save_info == FIRST o save está
 * no início da fila interna (resultado do set_save_first do receive
 * anterior) e nenhum marker de receive pode estar ativo; pular para a
 * mensagem notificada é o mesmo resultado do scan linear, em O(1).
 *
 * Caminho O(1): se a mensagem casada entrou na fila interna por um
 * caminho instrumentado (fetch), o campo pon_in_link dela guarda o
 * endereco do ponteiro da fila principal que aponta para ela
 * (prev->next ou &sig_qs.first). Basta apontar o save para la — sem
 * caminhar a lista, sem pattern matching por mensagem.
 *
 * A validacao "*pon_in_link == matched_msg" garante que o link ainda
 * aponta para a mensagem casada. Se nao (mensagem consumida por outra
 * via, link reescrito, ou caminho nao instrumentado), a Premise esta
 * obsoleta: limpa o estado dela e retorna sem mexer no save — o scan
 * linear normal continua (correto, apenas mais lento).
 *
 * Se o save ja esta NA posicao da mensagem casada (jump feito por uma
 * chamada anterior cuja clausula nao casou, ou mensagem alcancada pelo
 * scan), a Premise tambem esta obsoleta para esta passada: limpa e
 * retorna, evitando loop infinito de re-jump para a mesma mensagem.
 *
 * Multi-clausula: a mensagem selecionada e a de MENOR sequencia de
 * chegada (pon_seq) entre as Premises satisfeitas — o receive seletivo
 * escolhe a mensagem mais antiga que casa QUALQUER clausula; a ordem
 * das clausulas so decide qual clausula casa dentro da mensagem.
 */
int
 erts_pon_advance_to_matched(Process *p)
{
    ErtsSignalPrivQueues *qs;
    ErtsPremise *best;
    ErtsPremise *prem;
    ErtsMessage *m;
    ErtsMessage *cur;
    ErtsMessage **orig_save;

    ASSERT(p != NULL);

    if (!p->pon_premises)
        return 0;

    qs = &p->sig_qs;
    best = NULL;
    m = NULL;
    cur = NULL;
    orig_save = NULL;

#define PON_DBG_DUMP(COND, MSG)                                         \
    do {                                                                \
        static int pon_dbg_n = 0;                                       \
        if ((COND) && pon_dbg_n < 300) {                                \
            pon_dbg_n++;                                                \
            fprintf(stderr, "PON-ADV #%d %s save=%p save_info=%d "      \
                    "cont=%d flags=%x best=%p m=%p link=%p\n",          \
                    pon_dbg_n, (MSG), (void*) qs->save,                  \
                    ERTS_MQ_GET_SAVE_INFO(p), (int) qs->cont,           \
                    (int) qs->flags, (void*) best, (void*) m,           \
                    (void*) (m ? m->pon_in_link : NULL));               \
        }                                                               \
    } while (0)

    /*
     * Gate de segurança: o jump so e valido no inicio do scan de um
     * receive (save_info FIRST, sem markers/prio). Em qualquer outro
     * estado (scan em andamento, receive com marker RCVM, prio queue),
     * o scan normal deve continuar intocado.
     */
    if (ERTS_MQ_GET_SAVE_INFO(p) != FS_SET_SAVE_INFO_FIRST) {
        PON_DBG_DUMP(1, "gate-saveinfo");
        return 0;
    }
    if (qs->cont
        || (qs->flags & (FS_PRIO_MQ | FS_PRIO_MQ_END_MARK | FS_PRIO_MQ_SAVE))) {
        PON_DBG_DUMP(1, "gate-cont-prio");
        return 0;
    }

    /* Melhor Premise = menor pon_seq (chegada mais antiga) com has_match */
    best = NULL;
    prem = p->pon_premises;
    while (prem) {
        if (prem->has_match) {
            if (!best || prem->matched_msg->pon_seq < best->matched_msg->pon_seq)
                best = prem;
        }
        prem = prem->next_premise;
    }

    if (!best) {
        PON_DBG_DUMP(1, "no-best");
        return 0;
    }

    m = best->matched_msg;
    cur = *qs->save;

    /* Save aponta para algo que nao e mensagem (marker): nao mexer. */
    if (cur && !ERTS_SIG_IS_MSG(cur)) {
        PON_DBG_DUMP(1, "cur-not-msg");
        return 0;
    }

    /*
     * Caminho O(1): link de entrada registrado no fetch e ainda valido,
     * e o save ainda nao alcancou a mensagem casada.
     */
    if (m && m->pon_in_link && *m->pon_in_link == m
        && qs->save != m->pon_in_link) {
        qs->save = m->pon_in_link;
        PON_STATS_INC(mailbox_scans_avoided);
        return 1;
    }
    PON_DBG_DUMP(1, "o1-fail");

    /*
     * Premise obsoleta: mensagem consumida por outra via (link
     * reescrito) ou ja alcancada pelo scan (save na posicao dela).
     * Limpa o estado para que futuras chegadas notifiquem de novo;
     * o scan linear normal prossegue do save atual.
     */
    if (!m || !m->pon_in_link || *m->pon_in_link != m
        || qs->save == m->pon_in_link) {
        best->has_match = 0;
        best->matched_term = THE_NON_VALUE;
        best->matched_msg = NULL;
        return 0;
    }

    /* Fallback: anda com o save pointer até a mensagem casada */
    orig_save = qs->save;
    while (cur && cur != m) {
        if (!cur->pon_in_link)
            cur->pon_in_link = qs->save;
        erts_msgq_set_save_next(p);
        cur = *qs->save;
    }
    if (cur && cur == m && !m->pon_in_link) {
        m->pon_in_link = qs->save;
    }

    if (!cur) {
        /* Não encontrada à frente: Premise obsoleta. Restaura o save
         * para o scan normal continuar; a Premise será re-notificada
         * quando uma nova mensagem compatível chegar. */
        qs->save = orig_save;
        best->has_match = 0;
        best->matched_term = THE_NON_VALUE;
        best->matched_msg = NULL;
        return 0;
    }

    PON_STATS_INC(mailbox_scans_avoided);
    return 1;
}

/*
 * Chamada pelo remove_message do interpreter: a mensagem consumida
 * satisfez uma (ou mais) Premise(s); limpa o estado para que futuras
 * chegadas possam notificar novamente.
 */
void
 erts_pon_note_message_consumed(Process *p, ErtsMessage *msgp)
{
    ErtsPremise *prem;

    ASSERT(p != NULL);
    ASSERT(msgp != NULL);

    prem = p->pon_premises;
    while (prem) {
        if (prem->matched_msg == msgp) {
            prem->has_match = 0;
            prem->matched_term = THE_NON_VALUE;
            prem->matched_msg = NULL;
        }
        prem = prem->next_premise;
    }
}

#endif /* PON_BEAM */
