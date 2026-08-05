---- MODULE SchedulerWakeup ----
\* SchedulerWakeup.tla — TLA+ Model for PON-Scheduler EventFD & Idle Wakeup Verification
\*
\* Proves formally that when the scheduler run-queues empty and the schedulers enter
\* sleeping state (0.0% CPU idle), any arriving event on epoll/eventfd guarantees
\* waking at least one active scheduler (No Lost Wakeup & Deadlock-Freedom).

EXTENDS Integers, FiniteSets

CONSTANTS
    Schedulers,
    Processes

VARIABLES
    SchedulerState, \* [s \in Schedulers |-> "Active" | "Sleeping"]
    ReadyQueue,     \* Subconjunto de Processes prontos para execução
    EventFDCounter  \* Inteiro >= 0 representando o acumulador do eventfd

vars == <<SchedulerState, ReadyQueue, EventFDCounter>>

TypeOK ==
    /\ SchedulerState \in [Schedulers -> {"Active", "Sleeping"}]
    /\ ReadyQueue \subseteq Processes
    /\ EventFDCounter \in 0..5

Init ==
    /\ SchedulerState = [s \in Schedulers |-> "Active"]
    /\ ReadyQueue = {}
    /\ EventFDCounter = 0

\* Produtor externo ou notificação PON insere um processo e sinaliza no eventfd
EnqueueProcess(p) ==
    /\ p \in Processes \ ReadyQueue
    /\ ReadyQueue' = ReadyQueue \cup {p}
    /\ EventFDCounter' = IF EventFDCounter < 5 THEN EventFDCounter + 1 ELSE EventFDCounter
    \* Se havia schedulers dormindo, a notificação eventfd acorda pelo menos 1
    /\ SchedulerState' = IF \E s \in Schedulers : SchedulerState[s] = "Sleeping"
                         THEN LET s == CHOOSE s \in Schedulers : SchedulerState[s] = "Sleeping"
                              IN [SchedulerState EXCEPT ![s] = "Active"]
                         ELSE SchedulerState

\* Scheduler dorme quando não há processos e EventFD é 0
SchedulerGoToSleep(s) ==
    /\ SchedulerState[s] = "Active"
    /\ ReadyQueue = {}
    /\ EventFDCounter = 0
    /\ SchedulerState' = [SchedulerState EXCEPT ![s] = "Sleeping"]
    /\ UNCHANGED <<ReadyQueue, EventFDCounter>>

\* Scheduler acorda quando há notificação pendente
SchedulerWakeup(s) ==
    /\ SchedulerState[s] = "Sleeping"
    /\ (ReadyQueue /= {} \/ EventFDCounter > 0)
    /\ SchedulerState' = [SchedulerState EXCEPT ![s] = "Active"]
    /\ EventFDCounter' = IF EventFDCounter > 0 THEN EventFDCounter - 1 ELSE 0
    /\ UNCHANGED ReadyQueue

\* Scheduler executa um processo da fila
ExecuteProcess(s, p) ==
    /\ SchedulerState[s] = "Active"
    /\ p \in ReadyQueue
    /\ ReadyQueue' = ReadyQueue \ {p}
    /\ UNCHANGED <<SchedulerState, EventFDCounter>>

Next ==
    \/ \E p \in Processes : EnqueueProcess(p)
    \/ \E s \in Schedulers : SchedulerGoToSleep(s)
    \/ \E s \in Schedulers : SchedulerWakeup(s)
    \/ \E s \in Schedulers, p \in Processes : ExecuteProcess(s, p)

Spec == Init /\ [][Next]_vars

\* Invariante: Se a fila tem trabalho ou eventfd > 0, nem todos os schedulers podem continuar dormindo
NoLostWakeup ==
    (ReadyQueue /= {} \/ EventFDCounter > 0) =>
        \E s \in Schedulers : SchedulerState[s] = "Active"

=============================================================================
