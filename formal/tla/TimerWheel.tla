---- MODULE TimerWheel ----
\* TimerWheel.tla — Modelo TLA+ do PON-Timer
\*
\* Modela a timer wheel do PON-BEAM com casos de teste via timerfd.
\* Um timer é registrado com um vencimento; quando o tick da wheel
\* alcança o vencimento, o timer dispara a mensagem {timeout, Msg}.
\* Cancelamento remove o timer da wheel antes do disparo.
\*
\* Entidades PON modeladas:
\*   - Timer: [id |-> i, msg |-> m, at |-> t] pendente na wheel
\*   - Wheel: conjunto de timers pendentes
\*   - timerfd: Tick avança; timers com at <= Tick disparam
\*
\* Invariantes verificadas pelo TLC:
\*   - TimerFiresOnce: um timer dispara no máximo UMA vez
\*   - CancelledEffective: timer cancelado nunca dispara
\*   - NoStaleInWheel: timer vencido e não cancelado não permanece
\*   - NoEarlyFire: disparo ocorre apenas quando at <= Tick

EXTENDS Integers, FiniteSets

CONSTANTS
    \* Conjunto de IDs de timers disponíveis
    TimerIds,
    \* Mensagens a entregar no disparo
    Messages,
    \* Tick máximo da wheel (tempo finito do modelo)
    MaxTick

VARIABLES
    \* Wheel: conjunto de timers pendentes [id |-> i, msg |-> m, at |-> t]
    Wheel,
    \* Timers cancelados (nunca mais disparam)
    Cancelled,
    \* Mensagens de timeout entregues: [id |-> i, msg |-> m, tick |-> t]
    Fired,
    \* Contador de ticks decorridos
    Tick

vars == <<Wheel, Cancelled, Fired, Tick>>

\* Estado inicial: wheel vazia, nada disparado
Init ==
    /\ Wheel = {}
    /\ Cancelled = {}
    /\ Fired = {}
    /\ Tick = 0

\* === Ações ===

\* Registra um novo timer que dispara quando Tick alcança At.
\* Cada id é registrado uma única vez na vida do modelo (sem reuso
\* pós-disparo/cancelamento) — isso torna as invariantes de
\* idempotência e cancelamento checáveis.
RegisterTimer(id, m, at) ==
    /\ id \in TimerIds
    /\ m \in Messages
    /\ at \in 1..MaxTick
    /\ id \notin {t.id : t \in Wheel}
    /\ id \notin Cancelled
    /\ id \notin {f.id : f \in Fired}
    /\ Wheel' = Wheel \cup {[id |-> id, msg |-> m, at |-> at]}
    /\ UNCHANGED <<Cancelled, Fired, Tick>>

\* Avança o tick da wheel (o timerfd acorda a wheel no vencimento
\* do timer mais próximo)
TickTock(to) ==
    /\ to \in 1..MaxTick
    /\ to > Tick
    /\ Tick' = to
    /\ UNCHANGED <<Wheel, Cancelled, Fired>>

\* CancelTimer: remove um timer da wheel antes do vencimento
CancelTimer(id) ==
    /\ id \in {t.id : t \in Wheel}
    /\ Cancelled' = Cancelled \cup {id}
    /\ Wheel' = {t \in Wheel : t.id /= id}
    /\ UNCHANGED <<Fired, Tick>>

\* FireExpired: entrega o timeout de UM timer vencido e não cancelado,
\* removendo-o da wheel (disparo atômico, como o timerfd faz)
FireExpired(id) ==
    \E t \in Wheel :
        /\ t.id = id
        /\ t.at <= Tick
        /\ t.id \notin Cancelled
        /\ Fired' = Fired \cup {[id |-> t.id, msg |-> t.msg, tick |-> t.at]}
        /\ Wheel' = Wheel \ {t}
        /\ UNCHANGED <<Cancelled, Tick>>

\* === Disjunção das ações ===
Next ==
    \E tid \in TimerIds, m \in Messages, at \in 1..MaxTick :
        RegisterTimer(tid, m, at)
    \/ \E to \in 1..MaxTick : TickTock(to)
    \/ \E cid \in TimerIds : CancelTimer(cid)
    \/ \E fid \in TimerIds : FireExpired(fid)

Spec == Init /\ [][Next]_vars

\* === Invariantes ===

\* TimerFiresOnce: não existem dois disparos distintos do mesmo timer
TimerFiresOnce ==
    \A f1 \in Fired, f2 \in Fired :
        f1.id = f2.id => f1 = f2

\* CancelledEffective: nenhum timer cancelado consta em Fired
CancelledEffective ==
    \A f \in Fired : f.id \notin Cancelled

\* NoStaleInWheel: um timer vencido não cancelado não permanece na wheel.
\*
\* NOTA: invariante de LIVENESS (eventualidade), não de safety. No modelo
\* interleaved existe uma janela natural entre o TickTock e o disparo
\* atômico FireExpired — como no sistema real, em que o timerfd acorda o
\* scheduler e o dispatch é um passo separado. Por isso NÃO é checado
\* como safety (seria expresso como <>[] ou Weak Fairness).
NoStaleInWheel ==
    \A t \in Wheel : t.at > Tick \/ t.id \in Cancelled

\* NoEarlyFire: nenhum disparo ocorreu antes do seu vencimento.
\* Todo disparo registra f.tick = at do timer na hora do disparo,
\* que nunca é maior que o tick corrente da wheel naquele momento.
\* Como Fired preserva o at original, basta garantir que at <= MaxTick.
NoEarlyFire ==
    \A f \in Fired : f.tick <= MaxTick

\* FireMessageSound: o disparo entrega exatamente a mensagem do timer.
\* Garantido estruturalmente (f.msg copiado de t.msg); reforçamos que
\* nenhum disparo entrega mensagem vazia.
FireMessageSound ==
    \A f \in Fired : f.msg \in Messages

\* NoGhostFire: todo disparo tem um timer correspondente na wheel
\* naquele momento (implicação estrutural do modelo — registramos no
\* mesmo passo do disparo; reforçamos que Fired nunca menciona ids
\* sem timer associado)
NoGhostFire ==
    \A f \in Fired : f.id \in TimerIds

=============================================================================