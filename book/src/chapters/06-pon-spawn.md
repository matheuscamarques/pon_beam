---
id: 06
titulo: "PON-Spawn: Immediate Notification"
parte: II
status: completed
dificuldade: facil
nota: Eliminating spawn polling latency in process creation.
fontes:
  - otp/erts/emulator/beam/erl_process.c
  - otp/erts/emulator/beam/erl_process.h
  - otp/erts/emulator/beam/pon_condition.c
  - otp/erts/include/internal/pon_condition.h
  - docs/RPT-03-pon-spawn.md
---

# 6. PON-Spawn: Immediate Notification

> *"A newly born process should not wait for the next polling cycle to come alive."*  
> — Matheus de Camargo Marques, 2025

---

## 6.1 Diagnosis: The Hidden Latency of Spawn

Creating an Erlang process is cheap (~5$\mu s$). However, when a child process is spawned, the target scheduler may be sleeping in `scheduler_wait()`. In stock BEAM, the target scheduler notices the new process only upon its next wakeup check (up to 1ms latency).

---

## 6.2 Proposal: Immediate Condition Notification

PON-Spawn hooks into `erts_schedule_process` (in `erl_process.c:7024`). When a process is enqueued into a scheduler's run queue, a direct NOP Condition notification triggers an immediate `eventfd` wake signal to the target scheduler.

```c
#ifdef PON_BEAM
static void erts_pon_schedule_notify(ErtsSchedulerData *esdp, Process *p) {
    if (esdp && esdp->pon_condition.active) {
        pon_condition_notify(&esdp->pon_condition, (void *)p);
    }
    PON_STATS_INC(condition_notifications);
}
#endif
```

![Chart 6: Spawn Latency Distribution (BEAM Stock vs PON-BEAM)](assets/charts/chart_6_spawn_latency_distribution.png)

---

## 6.3 Performance Impact

- **Spawn Wakeup Latency**: Reduced from $10-100\,\mu s$ down to **$1.0\,\mu s$**.
- **Burst Scalability**: Immediate activation of parallel worker pools without scheduler spin delays.

---

## 6.4 References & See Also

- [Chapter 1: The Problem](01-problema-polling.html)
- [Chapter 7: PON-Scheduler](07-pon-scheduler.html)
