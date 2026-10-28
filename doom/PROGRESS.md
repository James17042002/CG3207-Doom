# Progress log (doom branch)

Read this first when resuming work. Newest entries at the top.

## Status
Current milestone: **1 — Correctness** (not started)

## How to build and simulate
- Tools (Ubuntu): `apt-get install iverilog verilator gcc-riscv64-unknown-elf picolibc-riscv64-unknown-elf`
- Build C: `sw/common/build.sh sw/build/hello sw/hello/hello.c` -> `sw/build/hello.{irom,dmem}.mem`
- Simulate: `sim/run.sh sw/build/hello.irom.mem sw/build/hello.dmem.mem +quiet`
  - UART output is printed; a store to 0xFFFF00FC ends the sim (0 = PASS).
  - Plusargs: `+cycles=N +dip=HEX +pb=HEX +quiet +trace`
- RTL comes from the live Vivado sources: `project/project.srcs/sources_1/imports/`.
  To use a program on the board, copy the .mem files over `AA_IROM.mem` / `AA_DMEM.mem`.

## Log
### 2026-10-28 — Milestone 0 done
- Created `doom` branch, `sim/tb_wrapper.v` + `sim/run.sh` (Icarus), `sw/common/` (crt0, linker
  script, MMIO header, ELF -> .mem converter, build script).
- Existing AA_IROM program runs in sim (LED=ff, 7SEG=0x2a).
- `sw/hello/hello.c` compiled with GCC (rv32im, -Os) runs unmodified: prints over UART,
  mul/div/rem correct, exits PASS in 314 cycles. No hand-editing of compiler output needed.
- Note: constants (.rodata) are placed in DMEM because Wrapper.v cannot read IROM from the data port.
- Push access: vincesum's repo can't be pushed from Claude. Working copy targets the fork
  James17042002/CG3207-assignment-2 (to be renamed so it can be attached).
