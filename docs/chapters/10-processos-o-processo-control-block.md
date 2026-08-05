---
id: 10
title: "Processes & Process Control Block (PCB)"
part: I
status: validated
sources:
  - otp/erts/emulator/beam/erl_process.h
  - otp/erts/emulator/beam/erl_process.c
---

# Processes & Process Control Block (PCB)

In BEAM, Erlang processes are encapsulated by the `Process` struct in C (`erl_process.h`). Each PCB maintains the execution stack, heap pointers, reduction counters, signal queues, and status flags.
