---
id: 11
titulo: "The Fork Infrastructure"
parte: III
status: completed
dificuldade: medio
nota: Fork structure, conditional compilation via #ifdef PON_BEAM, Makefile targets, and 100% Erlang ABI compatibility.
fontes:
  - otp/erts/emulator/Makefile.in
  - otp/erts/configure.ac
  - AGENTS.md
---

# 11. The Fork Infrastructure

> *"Nothing changes in the .beam format, NIF ABI, or distribution protocols. PON-BEAM is 100% compatible."*  
> — PON-BEAM Engineering Plan

---

## 11.1 Introduction

PON-BEAM is a surgical re-architecture of the Erlang/OTP BEAM VM (experimental research branch `OTP 30.0-rc0`). Every NOP modification is isolated inside `#ifdef PON_BEAM` preprocessor blocks to preserve the baseline stock code intact. The build process produces a binary named `beam.ponbeam.smp`.

---

## 11.2 Conditional Compilation & Build Flags

Key build targets in `Makefile`:

- `make build-stock`: Compiles baseline stock Erlang/OTP (`beam.smp`).
- `make build-pon`: Compiles PON-BEAM (`beam.ponbeam.smp`) with `-DPON_BEAM`.
- `make build-pon-debug`: Compiles PON-BEAM with debug instrumentation and NOP counters (`-DPON_BEAM -DPON_DEBUG`).

---

## 11.3 File Layout

```
otp/erts/include/internal/
├── pon_premise.h
├── pon_instigation.h
├── pon_condition.h
├── pon_ets.h
├── pon_gc.h
└── pon_stats.h

otp/erts/emulator/beam/
├── pon_premise.c
├── pon_timer.c
├── pon_condition.c
├── pon_ets.c
└── pon_gc.c
```

---

## 11.4 References & See Also

- [Chapter 3: PON-BEAM Overview](03-visao-geral.html)
- [Chapter 12: The Benchmarking Harness](12-harness-benchmarking.html)
- [Repository Makefile](file:///home/sanonichan/projetos/pon-beam/Makefile)
