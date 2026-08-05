---
id: 05
title: "Term Representation: Type System, Tags, and Allocation Layout"
part: I
status: validated
difficulty: large
sources:
  - otp/erts/emulator/beam/erl_term.h
  - otp/erts/emulator/beam/erl_term.c
  - otp/erts/emulator/beam/global.h
  - otp/erts/emulator/beam/atom.h
  - otp/erts/emulator/beam/big.h
  - otp/erts/emulator/beam/big.c
  - otp/erts/emulator/beam/erl_bif_unique.h
---

# Term Representation: Type System, Tags, and Allocation Layout

> *"Visual and symbolic perception relies on the immediate detection of primary features in milliseconds prior to deep processing."*  
> — Stanislas Dehaene, *Reading in the Brain*, 2009

---

## 1. The Universal Type: `Eterm`

In the BEAM virtual machine, every Erlang/Elixir value (integers, atoms, tuples, lists, PIDs, binaries, maps) is represented internally in C by the same scalar type: the 64-bit word `Eterm` (`otp/erts/emulator/beam/erl_term.h:42`).

```c
typedef UWord Eterm;
```

To determine the value type without extra vtables or memory indirection, the BEAM employs **tagged pointers**. The least significant bits of the `Eterm` word store the **primary tag** of the value. Because 64-bit memory alignment is 8-byte aligned (ending in `000`), the lowest 3 bits are available for type metadata.

### The Four Primary Tags (2 bits)

The 2 least significant bits define the `primary_tag` (`erl_term.h:74-78`):

| Bit 1 | Bit 0 | C Constant | Description |
| :---: | :---: | :--- | :--- |
| `0` | `0` | `TAG_PRIMARY_HEADER` (`0x0`) | Header of heap-allocated object (tuples, maps, etc.) |
| `0` | `1` | `TAG_PRIMARY_LIST` (`0x1`) | Pointer to cons cell `[Head | Tail]` |
| `1` | `0` | `TAG_PRIMARY_BOXED` (`0x2`) | Pointer to boxed heap object |
| `1` | `1` | `TAG_PRIMARY_IMMED1` (`0x3`) | Immediate 0-word value (smallint, atom, pid, nil) |
