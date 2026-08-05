---
id: 08
title: "SMP Scheduler and Run Queue Architecture"
part: I
status: validated
difficulty: large
sources:
  - otp/erts/emulator/beam/erl_process.c
  - otp/erts/emulator/beam/erl_sched.h
---

# SMP Scheduler and Run Queue Architecture

> *"Order is not pressure imposed from without on chaos, but the harmony of elements from within."*  
> — Norbert Wiener, *Cybernetics*, 1948

---

## 1. Multi-Core Concurrency Model

BEAM operates a multi-threaded SMP scheduler architecture. By default, it spawns one OS thread per CPU core (`+S`). Each scheduler thread manages its own private run queues (`run_queue`) to minimize contention.

```dot
digraph schedulers {
  rankdir=LR;
  node [shape=box, style=rounded];

  "CPU Core 1" -> "Scheduler 1" -> "Run Queue 1";
  "CPU Core 2" -> "Scheduler 2" -> "Run Queue 2";
}
```

---

## 2. Reduction-Based Scheduling & Preemption

BEAM achieves soft real-time guarantees via **reductions** (function call budget, default $4,000$ reductions per timeslice).
