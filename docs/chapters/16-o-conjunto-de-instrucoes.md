---
id: 16
title: "The BEAM Instruction Set & Bytecode Execution Engine"
part: I
status: validated
sources:
  - otp/erts/emulator/beam/beam_emu.c
  - otp/erts/emulator/beam/ops.tab
---

# The BEAM Instruction Set & Bytecode Execution Engine

BEAM bytecode instructions are dispatched inside `process_main()` (`beam_emu.c`) via threaded code (computed `goto`).
