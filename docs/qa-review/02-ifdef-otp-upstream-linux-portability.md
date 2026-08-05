---
id: QA-02
title: "Maintainability via #ifdef PON_BEAM, Upstream OTP Tracking, and Linux Portability"
category: Engineering & Repository Strategy
status: reviewed
date: 2026-08-05
tags:
  - ifdef
  - upstream
  - linux
  - portability
  - eep
---

# QA-02: Maintainability via #ifdef PON_BEAM, Upstream OTP Tracking, and Linux Portability

## Question
> Do you think the `#ifdef PON_BEAM` approach makes tracking upstream Erlang/OTP updates easier? I imagine the Linux dependency would block any chance of upstreaming to the official Erlang/OTP repository.

---

## Detailed Technical & Strategic Answer

### 1. Does `#ifdef PON_BEAM` make tracking upstream OTP updates easier?

**Yes, substantially, but with structural trade-offs.**

#### Advantages of the Compilable Overlay Pattern:
1. **Change Isolation (*Non-Invasive Overlay*)**:
   Because project guidelines mandate that all C modifications in legacy ERTS files (`erl_process.c`, `erl_message.h`, `erl_proc_sig_queue.c`, etc.) are wrapped in `#ifdef PON_BEAM` and new logic lives in dedicated files (`pon_premise.c`, `pon_condition.c`, `pon_ets.c`), original baseline OTP code remains untouched.
2. **Simplified Rebasing & Merging**:
   When pulling or rebasing upstream OTP tags (e.g. upgrading from `30.0-rc0` to official OTP 30 or 31 releases), Git automatically resolves most merges because baseline OTP source code has not undergone un-guarded structural refactoring.
3. **Instant A/B Verification**:
   The entire codebase can be compiled with or without `-DPON_BEAM`, enabling zero-cost regression testing and performance differential benchmarks (*stock* vs *ponbeam*) within the exact same build tree.

#### Maintenance Costs & Limitations:
* **Internal Structure Drift**: If future OTP versions fundamentally restructure message representations (`ErtsMessage`) or process signal handling (`sig_qs`), code blocks inside `#ifdef PON_BEAM` referencing these internal fields will require manual refactoring.
* **Preprocessor Pollution**: Core VM maintainers typically avoid excessive `#ifdef` directives inside core loops to maintain readability.

---

### 2. Does the Linux dependency block upstreaming to official Erlang/OTP?

**In its current form, yes — and this is a critical architectural factor.**

#### Erlang/OTP Cross-Platform Portability Requirement:
Erlang/OTP is strictly **cross-platform**, with official tier-1 support for:
* **Linux** (`epoll`, `eventfd`, `timerfd`)
* **macOS / FreeBSD / OpenBSD** (`kqueue`, `EVFILT_USER`, `EVFILT_TIMER`)
* **Windows** (Win32 API, IOCP, `RegisterWaitForSingleObject`)
* **Solaris / Illumos** (`event ports`)
* **WebAssembly / Emscripten**

If PON-BEAM relies on Linux-specific primitives (`timerfd_create`, `eventfd`, `epoll_wait`) directly within scheduler or timer loops, the Erlang/OTP Core Team **would reject an upstream Pull Request**, as it breaks compilation on macOS, Windows, and BSDs.

---

### Architectural Roadmap for Upstream Integration

For PON-BEAM concepts to be considered for upstream integration (via an **EEP - Erlang Extension Proposal**), the architecture would need to evolve across two tiers:

```
                  ┌─────────────────────────────────────┐
                  │      PON-BEAM Reactive Layer (C)    │
                  │ (Premises, Conditions, Instigations) │
                  └──────────────────┬──────────────────┘
                                     │
                     ┌───────────────┴───────────────┐
                     ▼                               ▼
       ┌───────────────────────────┐   ┌───────────────────────────┐
       │   Linux HAL Backend       │   │    Darwin / BSD Backend   │
       │ (epoll + eventfd/timerfd) │   │ (kqueue + EVFILT_TIMER)   │
       └───────────────────────────┘   └───────────────────────────┘
```

1. **Hardware / OS Abstraction Layer (HAL / PAL)**:
   Similar to ERTS's existing `erts_poll.c`, PON instigations would require a platform-agnostic event backend:
   * **Linux**: `eventfd` / `timerfd` / `epoll`
   * **macOS/BSD**: `kqueue` user events and timer filters
   * **Windows**: IOCP (*Input/Output Completion Ports*) or Waitable Timers
2. **High-Performance Specialized Overlay**:
   As a doctoral research project and specialized VM for ultra-low latency workloads (similar to **ScyllaDB/Seastar** relative to Cassandra/C++), targeting bare-metal Linux directly allows extracting $100\%$ kernel performance without intermediate abstraction overhead.

---

### Summary Conclusion

* The `#ifdef PON_BEAM` strategy is optimal for the project: **it isolates research, prevents baseline corruption, and simplifies upstream OTP rebasing**.
* Linux primitive coupling is ideal for proving theoretical maximum performance gains, but requires an **OS abstraction layer** for eventual upstream Erlang/OTP submission.
