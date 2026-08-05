---
id: 25
title: "ETS & DETS Storage Systems Architecture"
part: I
status: validated
sources:
  - otp/erts/emulator/beam/erl_db.c
  - otp/erts/emulator/beam/erl_db.h
---

# ETS & DETS Storage Systems Architecture

Erlang Term Storage (ETS) provides in-memory key-value tables supporting `set`, `ordered_set`, `bag`, and `duplicate_bag` storage types.
