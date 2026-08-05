---
id: 11
title: "Messages & Mailbox Signal Architecture"
part: I
status: validated
sources:
  - otp/erts/emulator/beam/erl_message.h
  - otp/erts/emulator/beam/erl_message.c
---

# Messages & Mailbox Signal Architecture

Mailbox messaging in BEAM is structured around signal queues (`ErtsSignalPrivQueues`). Incoming cross-process signals are enqueued lock-free into `sig_inq` and fetched into `sig_qs` when the receiving process is scheduled.
