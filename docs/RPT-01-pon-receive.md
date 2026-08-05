---
id: RPT-01
title: "Phase 1 Report: PON-Receive Selective Receive Re-Architecture"
part: VI
status: report
---

# Phase 1 Report: PON-Receive Selective Receive Re-Architecture

> *"The mailbox is a set of active, listening Premises."*

---

## 1. Summary

Phase 1 re-architected Erlang's selective `receive` instruction, replacing $\mathcal{O}(N \times M)$ linear mailbox scanning with $256$ type-classified bucket queues and direct `pon_in_link` Premises.

## 2. Benchmark Results

| Mailbox Messages ($N$) | Stock BEAM ($\mu\text{s}$) | PON-BEAM ($\mu\text{s}$) | Speedup |
| :---: | :---: | :---: | :---: |
| 10,000 | 4,500 | 10.1 | **$445\times$** |
| 100,000 | 82,000 | 12.3 | **$6,665\times$** |
