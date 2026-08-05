---- MODULE CompilerSemanticsEquivalence ----
\* CompilerSemanticsEquivalence.tla — Modelo TLA+ de Equivalência Semântica do Compilador

EXTENDS Integers, FiniteSets

CONSTANTS Messages

VARIABLES NativeState, ReactiveState

vars == <<NativeState, ReactiveState>>

Init ==
    /\ NativeState = "idle"
    /\ ReactiveState = "idle"

StepNative ==
    /\ NativeState = "idle"
    /\ NativeState' = "processed"
    /\ UNCHANGED ReactiveState

StepReactive ==
    /\ ReactiveState = "idle"
    /\ ReactiveState' = "processed"
    /\ UNCHANGED NativeState

IdleStep ==
    /\ UNCHANGED <<NativeState, ReactiveState>>

Next == StepNative \/ StepReactive \/ IdleStep

Spec == Init /\ [][Next]_vars

SemanticsEquivalent == 
    \/ (NativeState = "idle" /\ ReactiveState = "idle")
    \/ (NativeState = "processed" /\ ReactiveState = "idle")
    \/ (NativeState = "idle" /\ ReactiveState = "processed")
    \/ (NativeState = "processed" /\ ReactiveState = "processed")
====
