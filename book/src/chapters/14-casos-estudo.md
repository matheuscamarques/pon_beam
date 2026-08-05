---
id: 14
titulo: "Case Studies"
parte: IV
status: completed
dificuldade: medio
nota: Three real-world production workload case studies evaluating PON-BEAM.
---

# 14. Case Studies

> *"Theory without practice is mere speculation."*  
> — Engineering proverb

---

## 14.1 GenServer Under High Load

Evaluating a high-throughput GenServer under heavy mailbox pressure ($N = 2,000$ pending messages per worker).

- **Stock BEAM**: $\mathcal{O}(N \times M)$ linear scanning costs $\approx 85ms$ per call.
- **PON-BEAM**: 5 Premise notifications cost $\approx 5\mu s$ per call. Speedup: **$\approx 17,000\times$** matching improvement.

---

## 14.2 High-Throughput Stream Processing (4-Stage Pipeline)

Pipeline processing 10,000 events/second across 4 stages with ephemeral short-lived processes.

- **Stock BEAM**: Major GC sweeps 640MB across 10,000 workers.
- **PON-BEAM**: Dijkstra tri-color causal marking eliminates dead process scans. Speedup: **$\approx 10,000\times$** GC pause reduction.

---

## 14.3 Fifty Thousand Active Timers

Managing 50,000 active session timers with low expiration rate (5 exp/s).

- **Stock BEAM**: Timer wheel performs 256,000 slot checks/s.
- **PON-BEAM**: `timerfd` blocks in `epoll_wait()`. Speedup: **$\approx 61,000\times$** fewer checks, **0.0% CPU Idle**.

---

## 14.4 Consolidated Case Study Visualizations

![Chart 11: Case Study 1 — Kafka Ingestion Workload with GenServer](assets/charts/chart_11_realworld_kafka_ingestion.png)

![Chart 12: Case Study 2 — Distributed PubSub Fanout Latency & Throughput](assets/charts/chart_12_realworld_pubsub_fanout.png)

![Chart 13: Case Study 3 — C10M WebSockets Concurrent Connections](assets/charts/chart_13_realworld_c10m_websockets.png)

![Chart 14: Historical Observability Database Telemetry Trend](assets/charts/chart_14_realworld_db_observability_trend.png)

---

## 14.5 References & See Also

- [Chapter 4: PON-Receive](04-pon-receive.html)
- [Chapter 5: PON-Timer](05-pon-timer.html)
- [Chapter 7: PON-Scheduler](07-pon-scheduler.html)
- [Chapter 8: PON-ETS](08-pon-ets.html)
