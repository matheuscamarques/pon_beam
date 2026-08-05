---
id: EX-36
title: Hypatia — Cross-Layer Self-Optimizing Architecture Proposal for Next-Gen BEAM
part: VI
status: thesis_proposal
sources:
  - otp/erts/emulator/beam/erl_gc.c
  - otp/erts/emulator/beam/erl_process.c
  - otp/erts/emulator/beam/erl_process.h
  - otp/erts/emulator/beam/beam_emu.c
  - otp/erts/emulator/beam/beam_opcodes.tab
  - otp/erts/emulator/beam/erl_alloc.c
  - otp/erts/emulator/beam/erl_db.c
  - otp/erts/emulator/beam/erl_sched.h
  - otp/lib/compiler/src/beam_ssa.erl
  - otp/lib/compiler/src/compile.erl
  - otp/erts/emulator/beam/jit/beam_jit_main.cpp
---

# Hypatia — Cross-Layer Self-Optimizing Architecture for the BEAM

> *"Truth is so precious that she should always be attended by a bodyguard of lies."* — Winston Churchill  

> **About the Author.** Matheus de Camargo Marques. This document presents an original thesis proposal outlining a cross-layer feedback VM architecture named **Hypatia**.

---

## Abstract

The BEAM Virtual Machine completes four decades of incremental evolution. Each internal subsystem — scheduler, garbage collector, compiler, JIT, memory allocator, distribution protocol — was designed with minimal cross-boundary communication. This thesis proposes the **Cross-Layer Architecture**, named **Hypatia**, where type information, execution telemetry profiles, inter-process communication graphs, and hardware topology form a continuous feedback loop across all VM execution layers.

Named in honor of Hypatia of Alexandria (c. 350–415 AD), who synthesized mathematics, astronomy, and philosophy in an era of knowledge fragmentation.

```dot
digraph hipatia {
  rankdir=TB;
  splines=polyline;

  subgraph cluster_compiler {
    label="Compiler & JIT Pass";
    color=blue;
    compiler [label="Compiler / JIT\n(beam_ssa)"];
    jit [label="JIT Engine\n(Type-guided)"];
  }

  subgraph cluster_runtime {
    label="ERTS Runtime Engine";
    color=green;
    sched [label="Scheduler\n(Topology-aware)"];
    gc [label="GC Engine\n(Adaptive)"];
    msg [label="Message Transport\n(Zero-copy)"];
  }

  subgraph cluster_feedback {
    label="Continuous Telemetry Mesh";
    color=purple;
    telemetry [label="Telemetry & Profiling\n(Hypatia Loop)"];
  }

  compiler -> jit -> sched -> gc -> msg -> telemetry -> compiler;
}
```
