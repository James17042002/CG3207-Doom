# Doom on the CG3207 RISC-V processor — plan

Goal: run Doom (doomgeneric) on our pipelined RV32IM core on the Nexys 4 DDR, shown on the
96x64 Pmod OLEDrgb (downscaled from 320x200).

## Key decisions
- Memory: 128 MB DDR2 via Xilinx MIG (generated in Vivado by us), with I/D caches in front.
  Simulated here against a behavioural model of the MIG user interface.
- Loading: UART bootloader copies the program and WAD into DDR2 from the PC.
- Port: doomgeneric (needs DG_DrawFrame, DG_GetTicksMs, DG_SleepMs, DG_GetKey, DG_Init).
- Display: 320x200 framebuffer in memory -> downscale -> OLED (VGA stays an option).
- Input: push buttons for movement + keys over UART.

## Milestones
0. Setup: branch, simulators, RISC-V toolchain, command-line testbench.  
1. Correctness: add mulhsu; run riscv-tests (rv32ui, rv32um) on the core in simulation.
2. Block RAM + clock: synchronous BRAM memories, pipeline-wide memory stall. Keep >= 50 MHz
   (teammate reports ~70 MHz on the current design). *Team: check timing in Vivado.*
3. Real C: linker script, crt0, picolibc; C compiles straight to memory images. *Team: board test.*
4. DDR2 + caches against a MIG UI model. *Team: generate MIG, board test.* (Riskiest step.)
5. UART loader for programs and the WAD.
6. OLED framebuffer path (320x200 -> 96x64).
7. Doom in Verilator; dump first frames as images.
8. Doom on the board; then speed (branch prediction, bigger caches, low detail).

## Division of work
Claude (cloud): RTL, software, simulation. Team (local): Vivado synthesis, timing, MIG, bitstream, board tests.
