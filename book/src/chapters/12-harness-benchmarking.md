---
id: 12
titulo: "The Benchmarking Harness"
parte: III
status: completed
dificuldade: medio
nota: Comparative benchmarking harness, metrics collection, automated HTML diff reports, and SQLite observability database.
fontes:
  - harness/run.sh
  - harness/benchmarks/lib/pon_harness.erl
  - harness/benchmarks/lib/pon_diff.erl
---

# 12. The Benchmarking Harness

> *"Without a diff proving performance gains, the phase is not complete."*  
> — AGENTS.md

---

## 12.1 Introduction

Every phase of PON-BEAM followed a cycle: modify ERTS $\rightarrow$ compile $\rightarrow$ run benchmark $\rightarrow$ generate diff $\rightarrow$ commit. The core of this cycle is the *benchmarking harness* — a set of shell scripts and Erlang modules executing identical workloads on both ERTS builds (`beam.smp` stock vs `beam.ponbeam.smp`).

---

## 12.2 Harness Architecture & Telemetry Database

- **Script Entry Point**: `./harness/run.sh`
- **Erlang Support Library**: `pon_harness.erl`, `pon_diff.erl`, `pon_stats_reader.erl`.
- **SQLite Database Schema**:
  - `telemetry_runs` (run_id, timestamp, erts_target, build_type).
  - `benchmark_results` (test_name, parameter_N, avg_latency, p99, throughput, cpu_idle_pct, memory_allocated).

![Chart 4: Telemetry Marathon Timeseries (10 Minutes with 100K Entities)](assets/charts/chart_4_marathon_timeseries.png)

![Chart 5: Dual Axis Telemetry (Throughput vs CPU Utilization)](assets/charts/chart_5_marathon_dual_axis.png)

![Chart 9: Context Switch Trendline (Voluntary / Involuntary)](assets/charts/chart_9_context_switches_trendline.png)

---

## 12.3 Automated HTML Diff Report Generation

Run outputs automatically generate a comparative report in `results/TIMESTAMP/diff/index.html` displaying side-by-side metrics, statistical speedup ratios ($\frac{\text{Stock}}{\text{PON}}$), and color-coded threshold highlights.

---

## 12.4 References & See Also

- [Chapter 11: The Fork Infrastructure](11-infraestrutura-fork.html)
- [Harness Entry Script `harness/run.sh`](file:///home/sanonichan/projetos/pon-beam/harness/run.sh)
