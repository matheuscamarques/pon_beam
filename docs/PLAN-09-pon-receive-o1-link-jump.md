# PLAN-09 — PON-Receive: True O(1) `advance_to_matched` via `pon_in_link`

## 1. Goal

Phase 1 (PON-Receive), Stage D: make save pointer positioning in `receive` **strictly $\mathcal{O}(1)$**, proving the core thesis "mailbox scanning does not scale".

Previously, `erts_pon_advance_to_matched` (invoked during `loop_rec` when a Premise matches) traversed the queue via pointer chasing (`cur = cur->next`) until reaching the matched message ($\mathcal{O}(\text{distance})$). Target: direct pointer assignment `qs->save = m->pon_in_link` — $\mathcal{O}(1)$ — proving flat latency vs mailbox size $N$.

---

## 2. Verified Baseline

- Commit `157d3a1` (Stage C) baseline:
  - `pon_fastpath_test2` $N=5000 \to 20\,\mu\text{s}$, $N=10 \to 4\,\mu\text{s}$.
  - Phase 1 Harness: PON 14.2/15.4 ms vs stock 14.6/17.2 ms @ 100K.

---

## 3. O(1) Design: `pon_in_link` (Inbound Link)

- Field `ErtsMessage **pon_in_link` in `struct erl_mesg` (guarded by `#ifdef PON_BEAM`):
  Points to the memory address of the internal queue pointer pointing TO the message (the `next` field of the predecessor; `&sig_qs.last` for head).
- Written during **fetch** (`erts_proc_sig_fetch__`) when moving `sig_inq` $\to$ internal queue.
- On advance: if `m->pon_in_link && *m->pon_in_link == m`, `qs->save = m->pon_in_link` $\to \mathcal{O}(1)$.
- Fallback: linear traversal fallback if queue state changed.