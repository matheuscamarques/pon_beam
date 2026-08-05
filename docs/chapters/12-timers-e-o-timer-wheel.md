---
id: 12
title: "Timers & Hierarchical Timer Wheel"
part: I
status: validated
sources:
  - otp/erts/emulator/beam/erl_timer.c
  - otp/erts/emulator/beam/erl_hl_timer.c
---

# Timers & Hierarchical Timer Wheel

BEAM manages process timers (`erlang:send_after/3`, `erlang:start_timer/3`, `receive ... after`) via a hierarchical timer wheel structure (`ErtsTimerWheel`).
