# Progress log (doom branch)

Read this first when resuming work. Newest entries at the top.

## Status
Current milestone: **7 — Doom in simulation** (milestones 2-6 done in simulation; board steps pending)

## How to build and simulate
- Tools (Ubuntu): `apt-get install iverilog verilator gcc-riscv64-unknown-elf picolibc-riscv64-unknown-elf`
- Build C: `sw/common/build.sh sw/build/hello sw/hello/hello.c` -> `sw/build/hello.{irom,dmem}.mem`
- Simulate: `sim/run.sh sw/build/hello.irom.mem sw/build/hello.dmem.mem +quiet`
  - UART output is printed; a store to 0xFFFF00FC ends the sim (0 = PASS).
  - Plusargs: `+cycles=N +dip=HEX +pb=HEX +quiet +trace`
- RTL comes from the live Vivado sources: `project/project.srcs/sources_1/imports/`.
  To use a program on the board, copy the .mem files over `AA_IROM.mem` / `AA_DMEM.mem`.

## Log
### 2026-10-28 — SoC, bootloader, Doom port (milestones 2-6, simulation)
- New SoC in `doom/rtl` (see `doom/README.md`): rv_core with whole-pipeline stall, boot RAM,
  16 KB I/D caches, MIG bridge with clock crossing, MMIO (UART FIFOs, timers, OLED, LEDs...).
- riscv-tests pass on the SoC from DDR2 through the caches (`doom/sim/rvtests/run.sh`, 48/48).
- `doom/sw/tests/memtest.c` passes in Verilator (9.3 M cycles).
- Bootloader + `doom/tools/load.py`: program loaded over the UART and run, in simulation.
- Board files: `rtl/top_nexys4ddr.v`, `vivado/doom.xdc`, `vivado/mig.prj` (from Digilent's
  board file, native UI, strict ordering), `vivado/build.tcl`, `vivado/program.tcl`.
  Lint-clean in Verilator; synthesises in Yosys (~8.3k LUT, 5k FF, 16 BRAM36). Not yet run in Vivado.
- Doom: doomgeneric (fetched by `sw/doom/fetch.sh`) + `sw/doom/doomgeneric_cg3207.c` + `syscalls.c`
  (picolibc; WAD exposed as a read-only file). Builds; running in Verilator with Freedoom.
### 2026-10-28 — Milestone 1 done
- `tests/riscv-tests/run.sh` builds rv32ui + rv32um from riscv-tests with a minimal env
  (`tests/riscv-tests/env/riscv_test.h`) and runs each on the core. 48/48 pass
  (fence_i, ma_data skipped).
- Bugs found and fixed:
  - ALU.v: explicit sensitivity list missed N/V/C, so slt/slti/sltiu/sltu gave wrong results in
    simulation (sim/synth mismatch). Now `always @(*)`.
  - MCycle.v: signed division of a negative number by zero returned 1 instead of -1.
  - mulhsu implemented (new MCycle input MulSU, Decoder output MCycleSU).
- Wrapper.v: `SIM_MEM_DEPTH_BITS` define enlarges IROM/DMEM in simulation only.
### 2026-10-28 — Milestone 0 done
- Created `doom` branch, `sim/tb_wrapper.v` + `sim/run.sh` (Icarus), `sw/common/` (crt0, linker
  script, MMIO header, ELF -> .mem converter, build script).
- Existing AA_IROM program runs in sim (LED=ff, 7SEG=0x2a).
- `sw/hello/hello.c` compiled with GCC (rv32im, -Os) runs unmodified: prints over UART,
  mul/div/rem correct, exits PASS in 314 cycles. No hand-editing of compiler output needed.
- Note: constants (.rodata) are placed in DMEM because Wrapper.v cannot read IROM from the data port.
- Push access: vincesum's repo can't be pushed from Claude. Working copy targets the fork
  James17042002/CG3207-assignment-2 (to be renamed so it can be attached).
