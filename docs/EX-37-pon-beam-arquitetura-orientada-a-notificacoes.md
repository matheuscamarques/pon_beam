---
id: EX-37
title: PON-BEAM — A Notification-Oriented Virtual Machine Architecture
part: VI
status: thesis_spec
sources:
  - otp/erts/emulator/beam/erl_process.c
  - otp/erts/emulator/beam/erl_process.h
  - otp/erts/emulator/beam/erl_message.h
  - otp/erts/emulator/beam/erl_gc.c
  - otp/erts/emulator/beam/erl_alloc.c
  - otp/erts/emulator/beam/erl_db.c
  - otp/erts/emulator/beam/erl_timer.c
  - otp/erts/emulator/beam/beam_emu.c
  - otp/erts/emulator/beam/erl_sched.h
  - Simão & Stadzisz (2008–2009), Negrini (2019), Linhares (2015)
  - github.com/matheuscamarques/tec0301_pon
  - github.com/matheuscamarques/pon_feature_flag
---

# PON-BEAM — A Notification-Oriented Virtual Machine Architecture

> *"We cannot solve our problems with the same thinking we used when we created them."* — Albert Einstein

> **About the Author.** Matheus de Camargo Marques. This document presents an original thesis proposal applying Jean Marcelo Simão's Notification-Oriented Paradigm (PON / NOP) as a core architectural principle for redesigning the BEAM Virtual Machine. Previous works by the author include NOP implementations in Elixir/BEAM ([tec0301_pon](https://github.com/matheuscamarques/tec0301_pon), 2025) and NOP-inspired dynamic reactive compilation ([pon_feature_flag](https://github.com/matheuscamarques/pon_feature_flag), 2025).

---

## Abstract

The BEAM (Bogdan/Björn's Erlang Abstract Machine) is built on a hybrid execution model — polling and scanning in several core subsystems, notifications in others. Schedulers poll run queues; selective receive linearly scans mailboxes; garbage collection scans heap roots; ETS performs locked searches; and the timer wheel polls for expirations.

The Notification-Oriented Paradigm (PON / NOP), proposed by Jean Marcelo Simão (2005–2009), introduces a computational model where minimal, reactive, decoupled entities collaborate exclusively via point-to-point notifications, eliminating temporal redundancy (unnecessary re-evaluations) and structural redundancy (repeated search code).

This thesis proposes **PON-BEAM**: a virtual machine re-architecture where **every internal subsystem is redesigned as a reactive PON entity** — reactive, notifying, without polling, without scanning. The core contribution is novel: existing NOP literature applies the paradigm *on top of* existing platforms (C++, Java, Erlang, FPGA). No prior work proposes NOP as the foundational design principle *of the VM engine itself*.

```dot
digraph pon_beam_overview {
  rankdir=TB;
  splines=polyline;

  subgraph cluster_actual {
    label="Traditional BEAM (Hybrid Polling + Notification)"
    color=red;
    "Scheduler" [label="Scheduler\n(run queue polling)"]
    "Selective Receive" [label="Selective Receive\n(linear scanning)"]
    "GC" [label="GC\n(root scanning)"]
    "ETS" [label="ETS\n(locked lookup)"]
    "Timer" [label="Timer Wheel\n(expiration polling)"]
  }

  subgraph cluster_pon {
    label="PON-BEAM (Pure Notification)"
    color=green;
    "Sched-PON" [label="Scheduler\n(Condition notified)"]
    "Recv-PON" [label="Selective Receive\n(Notifying Premises)"]
    "GC-PON" [label="GC\n(mark-by-notification)"]
    "ETS-PON" [label="ETS\n(Notifying FBE Watcher)"]
    "Timer-PON" [label="Timer\n(timerfd Instigations)"]
  }

  "Scheduler" -> "Sched-PON" [style=dashed, label="  polling → notification"]
  "Selective Receive" -> "Recv-PON" [style=dashed, label="  scanning → Premises"]
  "GC" -> "GC-PON" [style=dashed, label="  scan → mark-by-notify"]
  "ETS" -> "ETS-PON" [style=dashed, label="  lookup → FBE Watcher"]
  "Timer" -> "Timer-PON" [style=dashed, label="  polling → instigation"]
}
```
