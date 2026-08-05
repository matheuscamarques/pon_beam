---
id: QA-01
title: "Message & Notification Delivery Ordering under High Concurrency"
category: Architecture & Concurrency
status: reviewed
date: 2026-08-05
tags:
  - pon-receive
  - concurrency
  - ordering
  - fifo
  - sequence-counter
---

# QA-01: Message & Notification Delivery Ordering under High Concurrency

## Question
> Replacing the selective receive mechanism with a notification-based approach in PON-BEAM eliminates the linear mailbox scan and reduces complexity to $\mathcal{O}(1)$. How does the PON-BEAM implementation handle message delivery ordering under high concurrency scenarios where multiple messages may be sent almost simultaneously? What mechanism is used by PON-BEAM to guarantee the correct processing order of notifications in such scenarios?

---

## Detailed Technical Answer

In **PON-BEAM**, message notification processing order under high concurrency is maintained by combining ERTS's atomic signal queue infrastructure with the monotonic sequencing mechanism of the **Notification-Oriented Paradigm (PON / NOP)**.

PON-BEAM **does not alter Erlang's causal delivery order (FIFO)**, but replaces linear list scanning with a resolution strategy based on **monotonic sequence counters** (`pon_seq`) and **direct pointer links** (`pon_in_link`).

---

### 1. Atomic Signal Queue Ingestion (`sig_inq`)

In Erlang/OTP, messages sent concurrently by multiple processes to a target process pass through the lock-free atomic signal queue (`sig_inq`) in [erl_proc_sig_queue.c](file:///home/sanonichan/projetos/pon-beam/otp/erts/emulator/beam/erl_proc_sig_queue.c). PON-BEAM preserves this atomic ingestion layer (without locks / via CAS), establishing a **total arrival order** in the physical mailbox buffer before any rule evaluation takes place.

### 2. Monotonic Sequence Tagging (`pon_seq`)

When messages are fetched into the process's internal queue and passed to the Premise notification engine in [pon_premise.c:L173](file:///home/sanonichan/projetos/pon-beam/otp/erts/emulator/beam/pon_premise.c#L173), each message is tagged with a global monotonic 64-bit sequence counter in the [`ErtsMessage`](file:///home/sanonichan/projetos/pon-beam/otp/erts/emulator/beam/erl_message.h#L258-L263) structure:

```c
/* erl_message.h */
#define PON_MESSAGE_REF_FIELDS__ \
    ; ErtsMessage **pon_in_link \
    ; Uint64 pon_seq
```

```c
/* pon_premise.c */
msg->pon_seq = erts_pon_next_msg_seq();
```

This `pon_seq` serves as an indisputable physical timestamp of the exact order in which the message landed in the process mailbox.

---

### 3. Lowest `pon_seq` Premise Selection (Erlang Mailbox Invariant)

In traditional Erlang, the fundamental selective receive rule dictates that the VM must **always consume the oldest message in the mailbox that satisfies any clause** of the `receive` expression.

When multiple messages arrive concurrently and notify different active `ErtsPremise` entities, PON-BEAM selects the winning Premise by evaluating the smallest `pon_seq` in [pon_premise.c:L329-L337](file:///home/sanonichan/projetos/pon-beam/otp/erts/emulator/beam/pon_premise.c#L329-L337):

```c
/* Best Premise = lowest pon_seq (oldest arrival) among satisfied Premises */
best = NULL;
prem = p->pon_premises;
while (prem) {
    if (prem->has_match) {
        if (!best || prem->matched_msg->pon_seq < best->matched_msg->pon_seq)
            best = prem;
    }
    prem = prem->next_premise;
}
```

Thus:
- If message $M_1$ (with `pon_seq = 100`) matches Clause 2, and message $M_2$ (with `pon_seq = 101`) matches Clause 1, PON-BEAM selects $M_1$, since $100 < 101$.
- Clause index precedence (`clause_index`) is only used as a tie-breaker when a **single** message satisfies multiple clauses simultaneously.

---

### 4. $\mathcal{O}(1)$ Save Pointer Positioning via Inbound Link (`pon_in_link`)

Once the oldest matching message (`best->matched_msg`) is selected, PON-BEAM avoids an $\mathcal{O}(N)$ traversal to move the mailbox *save pointer*. During message fetch, the VM writes the exact memory address of the predecessor pointer in the internal linked queue into `msg->pon_in_link`:

```c
qs->save = m->pon_in_link; /* Instant save pointer positioning in O(1) */
```

---

### 5. Validation Gates and Fallback Mechanisms

To prevent race conditions under extreme edge cases (such as scheduler preemption or dynamic signal queue mutations):

1. **Pointer Validation**: Before completing the jump, PON-BEAM verifies `ASSERT(*pon_in_link == matched_msg)`.
2. **Execution State Gate**: Direct jump is only authorized if `save_info == FS_SET_SAVE_INFO_FIRST` (start of `receive` scan cycle, no active markers or priority queues).
3. **Safe Fallback**: If any state discrepancy is detected, the Premise state is invalidated and the VM safely falls back to standard linear scanning without breaking Erlang message semantics or losing messages.

---

### Summary of Ordering Mechanisms

| Layer | PON-BEAM Mechanism | Function in Ordering Guarantee |
| :--- | :--- | :--- |
| **Ingestion** | Atomic Signal Queue (`sig_inq`) | Preserves physical causal arrival order (FIFO) across sender processes |
| **Notification** | Monotonic `pon_seq` | Assigns an immutable arrival sequence ID to each mailbox message |
| **Resolution** | Min-Selection by `pon_seq` | Ensures selection of the oldest matching message (Erlang invariant) |
| **Execution** | Inbound Link (`pon_in_link`) | Positions mailbox read pointer in $\mathcal{O}(1)$ without queue traversal |
