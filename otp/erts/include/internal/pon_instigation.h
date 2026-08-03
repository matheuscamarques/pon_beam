/*
 * pon_instigation.h — Instigaes PON-BEAM
 *
 * Uma Instigation (Instigao) no PON dispa um mtodo de um FBE
 * quando uma condio temporal ou causal satisfeita.
 *
 * Na PON-BEAM, as Instigaes representam timers: em vez de
 * polling do timer wheel, cada Instigation usa timerfd (Linux)
 * para notificar o scheduler via epoll quando o tempo expira.
 *
 * S compilado quando PON_BEAM est definido.
 *
 * NOTA: Este header usa tipos C padro (uint64_t, int) para
 * no depender da cadeia completa de includes do OTP.
 */

#ifndef PON_INSTIGATION_H__
#define PON_INSTIGATION_H__

#ifdef PON_BEAM

#include <stdint.h>

/*
 * Tag de tipo de Instigation
 */
#define PON_INSTIGATION_TYPE_TIMER    1
#define PON_INSTIGATION_TYPE_SIGNAL   2

/* Forward declaration do Process OTP */
struct process;

/*
 * Estrutura base de uma Instigation PON.
 * Cada Instigation representa um evento futuro que notifica
 * um processo alvo quando ocorre.
 */
typedef struct ErtsInstigation_ {
    int                    type;            /* PON_INSTIGATION_TYPE_* */
    int                    fired;           /* 1 se j disparou */
    struct process        *target;          /* Processo a ser notificado */
    uint64_t               message;         /* Mensagem a enviar (termo Erlang) */
    struct ErtsInstigation_ *next;
} ErtsInstigation;

/*
 * Instigation temporal: usa timerfd do kernel para notificao.
 */
typedef struct {
    ErtsInstigation        base;
    int                    timer_fd;        /* timerfd (-1 se inativo) */
    uint64_t               expiration_ms;   /* Tempo absoluto de expirao */
} ErtsTimerInstigation;

/*
 * Inicializa uma Instigation timer.
 */
#define ERTS_INIT_TIMER_INSTIGATION(INST, TARGET, MSG, TIMEOUT_MS)               \
    do {                                                                          \
        (INST)->base.type       = PON_INSTIGATION_TYPE_TIMER;                      \
        (INST)->base.fired      = 0;                                               \
        (INST)->base.target     = (struct process *)(TARGET);                      \
        (INST)->base.message    = (MSG);                                           \
        (INST)->base.next       = NULL;                                            \
        (INST)->timer_fd        = -1;                                              \
        (INST)->expiration_ms   = (uint64_t)(TIMEOUT_MS);                          \
    } while (0)

/*
 * Cria uma nova Instigation timer com timerfd.
 * Retorna 0 em sucesso, -1 em erro/fallback.
 */
int pon_timer_instigation_create(ErtsTimerInstigation *inst);

/*
 * Cancela uma Instigation timer.
 */
void pon_timer_instigation_cancel(ErtsTimerInstigation *inst);

/*
 * Processa uma expirao de timerfd.
 */
void pon_timer_instigation_fire(ErtsTimerInstigation *inst);

/*
 * Inicializa o subsistema de timers PON.
 */
void pon_timer_init(void);

/*
 * Finaliza o subsistema de timers PON.
 */
void pon_timer_destroy(void);

#endif /* PON_BEAM */
#endif /* PON_INSTIGATION_H__ */
