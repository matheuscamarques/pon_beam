---
id: 15
titulo: "Related Work and Positioning"
parte: IV
status: completed
dificuldade: medio
nota: Literature review comparing PON-BEAM against existing concurrent VMs and reactive architectures.
---

# 15. Related Work and Positioning

> *"If I have seen further, it is by standing on the shoulders of Giants."*  
> — Isaac Newton

---

## 15.1 Original NOP (Simão & Stadzisz, 2008–2009)

The Notification-Oriented Paradigm (NOP) was formalized by Jean Marcelo Simão and Pedro C. Stadzisz (2008–2009). While original NOP applied NOP concepts to application-level software development, **PON-BEAM is the first work to apply NOP internally as a core virtual machine architecture**.

---

## 15.2 Comparative Positioning Matrix

| Comparative Dimension | Stock Erlang/OTP | Java Virtual Machine (JVM) | Go Runtime (Goroutines) | NOPL-Erlang (2025) | PON-BEAM |
|:---------------------:|:----------------:|:-------------------------:|:----------------------:|:------------------: |:--------:|
| **Mailbox Matching** | Linear scan $\mathcal{O}(N \times M)$ | Queue polling | Channel select polling | Application NOP | **$\mathcal{O}(1)$ Premise Notification** |
| **Scheduler Idle** | Spin-wait + sleep | Thread parking | Netpoller / sysmon | Standard BEAM | **0.0% CPU Idle (`eventfd`)** |
| **Timer Subsystem** | Timer Wheel $\mathcal{O}(K)$ | Timer Queue / Epoll | Quad-Tree Netpoller | Standard BEAM | **`timerfd` NOP Instigations** |
| **Shared Data (ETS)** | Read Lock + CA Tree | ConcurrentHashMap | Mutex / Channels | Application NOP | **Side-Table NOP Watchers (9.97M ops/s)** |
| **Garbage Collection** | Generational Semi-space | ZGC / Shenandoah | Concurrent Tri-Color | Standard BEAM | **Dijkstra Tri-Color NOP Graph** |

---

## 15.3 References & See Also

- [Chapter 2: The Notification-Oriented Paradigm](02-paradigma-pon.html)
- [Chapter 3: PON-BEAM Overview](03-visao-geral.html)
- [Chapter 16: Conclusion](16-conclusao.html)
