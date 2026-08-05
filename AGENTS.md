# AGENTS.md — PON-BEAM Agentic Workflow & Engineering Rules

## Purpose

Build **PON-BEAM**: a complete re-architecture of the BEAM virtual machine (Erlang/OTP) using Jean Marcelo Simão's **Notification-Oriented Paradigm (PON)**. Each VM internal subsystem is redesigned as a reactive PON entity — eliminating polling, avoiding linear scans, and executing strictly via point-to-point notifications.

## Repository Structure

```
pon-beam/
├── otp/                          # Erlang/OTP 30.0-rc0 fork
│   └── erts/emulator/beam/      # ERTS — Where C modifications live
├── formal/                       # 4-Pillar Formal Verification Suite (TLA+, Coq, Frama-C, PropEr)
├── harness/                      # Comparative benchmark harness
│   ├── config/                   # ERTS path configs (baseline.sh, ponbeam.sh)
│   ├── benchmarks/               # Erlang benchmark suites
│   │   └── lib/                  # Base modules (pon_harness, pon_diff, pon_stats_reader)
│   ├── report/                   # Template and assets for HTML diff report
│   └── run.sh                    # Primary harness execution script
├── docs/                         # Specifications & engineering plans
├── book/                         # Interactive HTML book builder & chapter sources
├── Makefile                      # Primary build, benchmark, and verification entry point
└── AGENTS.md                     # This workflow guidelines file
```

## Branch Strategy

- `otp-30.0-rc0-stock` — Original, immutable OTP code. Never modify.
- `pon-beam` — Active working branch where PON modifications are applied.

## Implementation Phases

Each phase follows a complete cycle: Modify ERTS C code ➔ Compile ➔ Run Benchmark ➔ Generate Diff Report ➔ Commit.

| Phase | Subsystem | Target Files | Estimated Duration | Acceptance Criteria |
| :---: | :--- | :--- | :---: | :--- |
| **0** | Fork Infrastructure | `Makefile.in`, `configure.ac`, `pon_*.h` | 1-2 weeks | `make TYPE=ponbeam` produces functional `beam.ponbeam.smp` |
| **1** | PON-Receive | `erl_message.h`, `erl_process.c`, `pon_premise.h` | 4 weeks | `receive_mailbox_scan` exhibits $O(1)$ latency |
| **2** | PON-Timer | `erl_timer.c`, `pon_instigation.h` | 2 weeks | `timer_idle_cpu` exhibits 0.0% CPU idle waste |
| **3** | PON-Spawn | `erl_process.c` | 1 week | `spawn_latency` significantly reduced |
| **4** | PON-Scheduler | `erl_process.c`, `erl_sched.h`, `pon_condition.h` | 6 weeks | `sched_idle_cpu` exhibits 0.0% CPU idle waste |
| **5** | PON-ETS | `erl_db.c`, `erl_db.h` | 6 weeks | `ets_read_repeat` exhibits $\sim 1000\times$ speedup |
| **6** | PON-Compiler | `beam_ssa.erl`, `beam_opcodes.tab` | 4 weeks | `receive` clauses compile to native Premises |
| **7** | PON-GC | `erl_gc.c`, `erl_gc.h` | 8 weeks | `gc_heap_scan` exhibits $\sim 10\times$ scan reduction |

## Golden Rules

1. **Never modify the baseline.** Original OTP code resides in `otp-30.0-rc0-stock`. All modifications occur on branch `pon-beam`.
2. **Wrap all C modifications in `#ifdef PON_BEAM`.** The original code remains intact. PON-BEAM is a compilable overlay.
3. **Every phase delivers a differential benchmark.** A phase is incomplete without an empirical diff proving performance gains. The harness automatically generates the HTML diff.
4. **Benchmark before and after.** Always measure across both ERTS targets (`stock` vs `ponbeam`) with identical workloads.
5. **One commit per phase.** Commit message format: `feat(phase-N): <description> — validated`.

## Primary Commands

| Command | Action |
| :--- | :--- |
| `make build-stock` | Compiles Stock OTP 30 baseline |
| `make build-pon` | Compiles OTP with PON-BEAM ERTS |
| `make build-pon-debug` | Compiles PON-BEAM with debug telemetry counters |
| `make benchmark` | Runs full benchmark harness |
| `make benchmark-fase1` | Runs Phase 1 benchmark suite |
| `make benchmark-list` | Lists available benchmarks |
| `make verify-all` | Runs 4-Pillar Formal Verification suite (TLA+, PropEr, Frama-C) |
| `make report` | Opens latest HTML diff report |
| `make clean` | Cleans build artifacts |

## References

- PON-BEAM Thesis: `docs/EX-37-pon-beam-arquitetura-orientada-a-notificacoes.md`
- Engineering Plan: `docs/EX-38-pon-beam-plano-de-engenharia.md`
- Notification-Oriented Paradigm: Simão & Stadzisz (2008–2009)
