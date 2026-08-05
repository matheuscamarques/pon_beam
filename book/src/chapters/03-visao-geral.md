---
id: 03
titulo: "PON-BEAM Overview"
parte: I
status: completed
dificuldade: medio
nota: Architectural overview and structural mapping of PON-BEAM.
---

# 3. PON-BEAM Overview

> *"What if the VM itself were NOP from within?"*  
> — Matheus de Camargo Marques, 2025

---

## 3.1 Introduction

The first two chapters established the diagnosis and the cure. Chapter 1 demonstrated that the BEAM accumulates hidden polling costs — linear mailbox scanning, run queue polling, timer wheel ticking, ETS read lock contention, and major GC scans. Chapter 2 introduced Jean Marcelo Simão's Notification-Oriented Paradigm (NOP): a computational model where entities do not seek information, but *are notified* when relevant changes occur. This third chapter bridges both worlds.

We present the complete architectural map of the **PON-BEAM**: how each BEAM subsystem has been re-architected as a NOP entity, which entity replaces which mechanism, and how the notification pipeline flows end-to-end through the VM.

---

## 3.2 Architectural Map

The figure below contrasts the traditional BEAM architecture (hybrid polling + notification) with the PON-BEAM architecture (pure notification).

```dot
digraph pon_beam_overview {
  rankdir=TB; splines=polyline;
  subgraph cluster_actual {
    label="BEAM Stock (Hybrid Polling + Notification)"; color=red;
    "Scheduler" [label="Scheduler\n(run queue polling)"]
    "Selective Receive" [label="Selective Receive\n(linear scanning)"]
    "GC" [label="GC\n(root scanning)"]
    "ETS" [label="ETS\n(lock-based lookup)"]
    "Timer" [label="Timer Wheel\n(expiration polling)"]
  }
  subgraph cluster_pon {
    label="PON-BEAM (Pure Notification)"; color=green;
    "Sched-PON" [label="Scheduler\n(Condition eventfd)"]
    "Recv-PON" [label="Selective Receive\n(Notifying Premises)"]
    "GC-PON" [label="GC\n(Causal Chain Marking)"]
    "ETS-PON" [label="ETS\n(Notifying Watcher FBE)"]
    "Timer-PON" [label="Timer\n(timerfd Instigations)"]
  }
  "Scheduler" -> "Sched-PON" [style=dashed, label="  polling → notification"]
  "Sched-PON" -> "Selective Receive" [style=dashed, label="  scanning → Premises" dir=back]
  "GC" -> "GC-PON" [style=dashed, label="  scan → causal chain"]
  "ETS" -> "ETS-PON" [style=dashed, label="  lookup → watcher"]
  "Timer" -> "Timer-PON" [style=dashed, label="  polling → instigation"]
}
```

---

## 3.3 Structural Mapping: NOP Entity ↔ BEAM Subsystem

| NOP Entity | BEAM Subsystem | Responsibility |
|---|---|---|
| **FBE** | OTP Process | State (heap, mailbox, registers) + behavior |
| **Attribute** | Heap Terms | Values that notify upon change/read |
| **Premise** | Selective Receive Clause | Reactive pattern matching |
| **Condition** | Run Queue / Readiness | Aggregates Premises, notifies scheduler |
| **Rule** | VM Bytecode Opcodes | Condition → side effect dispatch |
| **Action** | BIFs, Send, Spawn | External side effects |
| **Instigation** | Timer, Preemption | Asynchronous temporal triggers |

![Chart 10: Comparative Asymptotic Complexity Matrix (BEAM Stock vs PON-BEAM)](assets/charts/chart_10_asymptotic_matrix_heatmap.png)

![Chart 8: Holistic Performance and Efficiency Radar of PON-BEAM](assets/charts/chart_8_radar_holistic_performance.png)

---

## 3.4 Git Lineage & Phase Milestones

- **Phase 0 (Fork Infrastructure)**: Builds `beam.ponbeam.smp` using `#ifdef PON_BEAM`.
- **Phase 1 (PON-Receive)**: $O(1)$ lazy save pointer positioning via `pon_in_link` in `erl_message.h`.
- **Phase 2 (PON-Timer)**: Replaces timer wheel ticking with Linux `timerfd_create`.
- **Phase 3 (PON-Spawn)**: Immediate process scheduling notification.
- **Phase 4 (PON-Scheduler)**: Zero CPU Idle (0.0%) via `eventfd` and `epoll_wait`.
- **Phase 5 (PON-ETS)**: Side-table watcher registry executing 9.97M ops/sec.
- **Phase 6 (PON-Compiler)**: AST parse transform rewriting `receive` to Premises.
- **Phase 7 (PON-GC)**: Dijkstra tri-color causal marking reducing GC pauses by 26.3%.

---

## 3.5 References & See Also

- [Chapter 1: The Problem](01-problema-polling.html)
- [Chapter 2: The Notification-Oriented Paradigm](02-paradigma-pon.html)
- [Chapter 4: PON-Receive](04-pon-receive.html)
- [Chapter 7: PON-Scheduler](07-pon-scheduler.html)
- [Chapter 11: The Fork Infrastructure](11-infraestrutura-fork.html)
