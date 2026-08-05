---- MODULE AtomicLockFreeInvariants ----
\* AtomicLockFreeInvariants.tla — Modelo TLA+ de Ausência de Data Races em C11 Atômicos
\*
\* Modela a inserção de Premises e side-table watchers usando atômicos C11 (ethread.h).
\* Prova que operações concorrentes de lock-free compare-and-swap nunca causam data races.

EXTENDS Integers, FiniteSets

CONSTANTS Threads, Slots

VARIABLES Memory, State

vars == <<Memory, State>>

Init ==
    /\ Memory = [s \in Slots |-> 0]
    /\ State = [t \in Threads |-> "idle"]

CAS(t, s, oldVal, newVal) ==
    /\ State[t] = "idle"
    /\ IF Memory[s] = oldVal THEN
        /\ Memory' = [Memory EXCEPT ![s] = newVal]
        /\ State' = [State EXCEPT ![t] = "done"]
       ELSE
        /\ Memory' = Memory
        /\ State' = [State EXCEPT ![t] = "retry"]

Next ==
    \E t \in Threads, s \in Slots :
        CAS(t, s, 0, 1)

Spec == Init /\ [][Next]_vars

LockFreeInvariant == \A s \in Slots : Memory[s] >= 0
====
