---
id: EX-38
title: PON-BEAM — Engineering Plan for Notification-Oriented Virtual Machine
part: VI
status: engineering_plan
authors:
  - Matheus de Camargo Marques (Architecture and Design)
sources:
  - EX-37-pon-beam-arquitetura-orientada-a-notificacoes.md
  - otp/erts/emulator/Makefile.in
  - otp/erts/configure.ac
  - otp/erts/emulator/beam/erl_process.c
  - otp/erts/emulator/beam/erl_message.h
  - otp/erts/emulator/beam/erl_timer.c
  - otp/erts/emulator/beam/erl_gc.c
  - otp/erts/emulator/beam/erl_db.c
  - otp/erts/emulator/beam/erl_sched.h
  - otp/erts/emulator/beam/beam_ssa.erl
---

# PON-BEAM — Engineering Plan

> *"The measure of intelligence is the ability to change."* — Albert Einstein

## Scope

This document specifies the **construction plan** for PON-BEAM: the modifications to ERTS (Erlang RunTime System) implementing the notification-oriented subsystems described in thesis `EX-37`.

Each phase delivers:
1. Modified C source code in ERTS (guarded by `#ifdef PON_BEAM`).
2. One or more Erlang microbenchmarks in the test harness.
3. An HTML differential benchmark report comparing baseline (Stock OTP 30) vs PON-BEAM.
4. Telemetry instrumentation counters in C validating internal behavior.

---

## 1. OTP Fork Structure

### 1.1 Repository & Branch Strategy

```
Upstream: https://github.com/erlang/otp (tag OTP-30.0-rc0)
Fork:     https://github.com/matheuscamarques/pon_beam (branch pon-beam)
```

The repository maintains an immutable baseline branch (`otp-30.0-rc0-stock`) and a working branch (`pon-beam`). Nothing changes in the `.beam` file format, NIF ABI, or distribution protocols — PON-BEAM is **100% backward-compatible with the existing Erlang/Elixir ecosystem**.
