/*
 * pon_premise.h — Premises PON-BEAM
 *
 * Definição da entidade Premise do Paradigma Orientado a Notificações
 * adaptada para o selective receive da BEAM.
 *
 * Uma Premise representa um padrão de mensagem compilado. Quando uma
 * mensagem compatível chega na mailbox, a Premise é notificada — em vez
 * de escanear a mailbox linearmente.
 *
 * Só compilado quando PON_BEAM está definido.
 */

#ifndef PON_PREMISE_H__
#define PON_PREMISE_H__

#ifdef PON_BEAM

#include "sys.h"
#include "erl_term.h"

/* Forward declaration — ErtsMessage é definido em erl_message.h */
struct erl_mesg;

/*
 * Tag de tipo para classificação rápida de mensagens.
 * Extraída do primeiro elemento da tupla mensagem.
 * Ex: {call, From, Req} -> tag = tag_atom(call) & 0xFF
 */
#define PON_TYPE_TAG_BITS  8
#define PON_NUM_TYPE_BUCKETS (1 << PON_TYPE_TAG_BITS)

#define pon_type_tag(term) ((Uint)(term) & (PON_NUM_TYPE_BUCKETS - 1))

/*
 * Estrutura de uma Premise.
 * Cada cláusula de `receive` compila para uma Premise.
 */
typedef struct ErtsPremise_ {
    Eterm                pattern;        /* Padrão compilado (como termo) */
    int                  (*match_fn)(Eterm); /* Função de match otimizada */
    int                  has_match;      /* 1 se há mensagem casada disponível */
    Eterm                matched_term;   /* Termo da mensagem casada */
    struct erl_mesg      *matched_msg;   /* Referência para a mensagem */
    Uint                 clause_index;   /* Índice da cláusula (ordem) */
    struct ErtsPremise_  *next_premise;  /* Lista ligada de premises */
} ErtsPremise;

/*
 * Inicializa uma Premise.
 */
#define ERTS_INIT_PREMISE(PREM, PAT, MATCH_FN, CIDX)                      \
    do {                                                                   \
        (PREM)->pattern      = (PAT);                                      \
        (PREM)->match_fn     = (MATCH_FN);                                 \
        (PREM)->has_match    = 0;                                          \
        (PREM)->matched_term = THE_NON_VALUE;                              \
        (PREM)->matched_msg  = NULL;                                       \
        (PREM)->clause_index = (CIDX);                                     \
        (PREM)->next_premise = NULL;                                       \
    } while (0)

/*
 * Registra uma lista de premises no processo.
 */
void erts_pon_register_premises(Process *p, ErtsPremise *premises);

/*
 * Remove todas as premises registradas no processo.
 */
void erts_pon_unregister_premises(Process *p);

/*
 * Função de match default (fallback): faz pattern matching completo.
 * Usada quando a Premise não tem match_fn especializada.
 */
int erts_pon_default_match(Eterm pattern, Eterm term);

/*
 * Notifica as premises do processo sobre a chegada de uma mensagem.
 * Retorna o número de premises que matcharam.
 */
int erts_pon_notify_premises(Process *p, struct erl_mesg *msg, Eterm term);

/*
 * Fast-path do selective receive (interpreter): avança o save pointer
 * da fila principal até a mensagem que a melhor Premise notificou.
 */
void erts_pon_advance_to_matched(Process *p);

/*
 * Chamada pelo remove_message: limpa o estado das Premises cuja
 * mensagem casada foi consumida.
 */
void erts_pon_note_message_consumed(Process *p, struct erl_mesg *msgp);

#endif /* PON_BEAM */
#endif /* PON_PREMISE_H__ */
