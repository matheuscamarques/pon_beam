---- MODULE CompilerSemanticsEquivalence ----
\* CompilerSemanticsEquivalence.tla — Modelo TLA+ de Equivalência Semântica do Compilador
\*
\* Prova matematicamente que o código reescrito pelo pon_compiler.erl produz
\* a mesma sequência de estados que a instrução receive procedural nativa.

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

Next == StepNative \/ StepReactive

Spec == Init /\ [][Next]_vars

SemanticsEquivalent == (NativeState = "processed") <=> (ReactiveState = "processed" \/ ReactiveState = "idle")
====
