---- MODULE AtomicLockFreeInvariants ----
\* AtomicLockFreeInvariants.tla — Modelo TLA+ de Ausência de Data Races em C11 Atômicos

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

IdleStep ==
    /\ \E t \in Threads : State[t] # "idle"
    /\ UNCHANGED <<Memory, State>>

Next ==
    \/ \E t \in Threads, s \in Slots : CAS(t, s, 0, 1)
    \/ IdleStep

Spec == Init /\ [][Next]_vars

LockFreeInvariant == \A s \in Slots : Memory[s] >= 0
====
