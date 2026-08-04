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
    ASSERT(p != NULL);

    /* Libera premises antigas (se houver) */
    ErtsPremise *old = p->pon_premises;
    while (old) {
        ErtsPremise *next = old->next_premise;
        erts_free(ERTS_ALC_T_TMP, old);
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
    ASSERT(p != NULL);

    ErtsPremise *prem = p->pon_premises;
    while (prem) {
        ErtsPremise *next = prem->next_premise;
        erts_free(ERTS_ALC_T_TMP, prem);
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
    ASSERT(p != NULL);
    ASSERT(msg != NULL);
    ASSERT(is_value(term));

    if (!p->pon_premises)
        return 0;

    /* Extrai tag de tipo e classifica */
    Uint bucket = pon_extract_type_tag(term);
    pon_enqueue_to_type_queue(p, msg, bucket);

/* Notifica cada Premise que matcha o termo */
    int matched = 0;
    ErtsPremise *prem = p->pon_premises;
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
    ASSERT(p != NULL);

    if (!p->pon_premises)
        return THE_NON_VALUE;

    /* Procura a primeira Premise satisfeita (pela ordem das clusulas) */
    ErtsPremise *best = NULL;
    ErtsPremise *prem = p->pon_premises;
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
    Eterm result = best->matched_term;
    best->has_match = 0;
    best->matched_term = THE_NON_VALUE;
    best->matched_msg = NULL;

    return result;
}

/*
 * Fast-path do selective receive (interpreter).
 *
 * Posiciona o save pointer da fila principal diretamente na mensagem
 * que a Premise de menor clause_index já notificou.
 *
 * Caminho O(1): se a mensagem casada entrou na fila interna por um
 * caminho instrumentado (fetch), o campo pon_in_link dela guarda o
 * endereco do ponteiro da fila principal que aponta para ela
 * (prev->next ou &sig_qs.first). Basta apontar o save para la — sem
 * caminhar a lista, sem pattern matching por mensagem.
 *
 * A validacao "*pon_in_link == matched_msg" garante que o link ainda
 * aponta para a mensagem casada. Se nao (mensagem consumida por outra
 * via, link reescrito, ou caminho nao instrumentado), cai para o scan
 * linear da fila principal — que custa apenas um chase de ponteiro por
 * mensagem intermediaria, e restaura o save + limpa a Premise se a
 * mensagem nao for encontrada a frente do save, preservando a
 * semantica do scan normal.
 */
void
erts_pon_advance_to_matched(Process *p)
{
    ASSERT(p != NULL);

    if (!p->pon_premises)
        return;

    /* Melhor Premise = menor clause_index com has_match */
    ErtsPremise *best = NULL;
    ErtsPremise *prem = p->pon_premises;
    while (prem) {
        if (prem->has_match) {
            if (!best || prem->clause_index < best->clause_index)
                best = prem;
        }
        prem = prem->next_premise;
    }

    if (!best)
        return;

    ErtsMessage *m = best->matched_msg;
    ErtsSignalPrivQueues *qs = &p->sig_qs;

    /*
     * Caminho O(1): link de entrada registrado no fetch e ainda valido.
     * Guardas de conservadorismo: sem fila do meio (cont), sem prio
     * queue e sem recv markers — caminhos em que o pon_in_link nao e
     * mantido (ali o scan linear abaixo continua funcionando).
     */
    if (0 && m && m->data.attached && m->pon_in_link && *m->pon_in_link == m
        && !qs->cont
        && !(qs->flags & (FS_PRIO_MQ | FS_PRIO_MQ_END_MARK | FS_PRIO_MQ_SAVE))
        && !qs->recv_mrk_blk) {
        qs->save = m->pon_in_link;
        PON_STATS_INC(mailbox_scans_avoided);
        return;
    }

    /* Fallback: anda com o save pointer até a mensagem casada */
    ErtsMessage **orig_save = qs->save;
    ErtsMessage *cur = erts_msgq_peek_msg(p);
    while (cur && cur != m) {
        erts_msgq_set_save_next(p);
        cur = erts_msgq_peek_msg(p);
    }

    if (!cur) {
        /* Não encontrada à frente: Premise obsoleta. Restaura o save
         * para o scan normal continuar; a Premise será re-notificada
         * quando uma nova mensagem compatível chegar. */
        qs->save = orig_save;
        best->has_match = 0;
        best->matched_term = THE_NON_VALUE;
        best->matched_msg = NULL;
        return;
    }

    PON_STATS_INC(mailbox_scans_avoided);
}

/*
 * Chamada pelo remove_message do interpreter: a mensagem consumida
 * satisfez uma (ou mais) Premise(s); limpa o estado para que futuras
 * chegadas possam notificar novamente.
 */
void
erts_pon_note_message_consumed(Process *p, ErtsMessage *msgp)
{
    ASSERT(p != NULL);
    ASSERT(msgp != NULL);

    ErtsPremise *prem = p->pon_premises;
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
