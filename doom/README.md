# Doom on the CG3207 RISC-V processor

This folder turns the course's 5-stage RV32IM pipeline into a small system-on-chip that can run
Doom on the Nexys 4 DDR, shown on the Pmod OLEDrgb (96×64). Everything here was developed and
tested in simulation; the steps that need Vivado and the board are listed in
[Bring-up on the board](#bring-up-on-the-board).

```
            +---------------------------- soc.v -----------------------------+
 buttons -->|  rv_core (RV.v + global stall)                                 |
 switches   |    |  instruction port          |  data port                   |
 UART <---->|    v                            v                              |
 OLED  <----|  boot RAM 16 KB (bootloader)   boot RAM / D-cache / mmio       |
 7-seg <----|  I-cache 16 KB ----+    +---- D-cache 16 KB (write-back)       |
            |                    v    v                                      |
            |               mem_bridge (arbiter + clock crossing)            |
            +-----------------------------|----------------------------------+
                                          v  ui_clk (81.25 MHz)
                                 Xilinx MIG -> DDR2 128 MB
```

## What is where

| Path | What |
|---|---|
| `rtl/rv_core.v` | The course pipeline (from `RV.v`) with synchronous memories and a whole-pipeline stall for cache misses |
| `rtl/soc.v` | Memory map, boot RAM, caches, bridge, peripherals |
| `rtl/icache.v`, `rtl/dcache.v` | Direct-mapped caches, 16-byte lines (D-cache is write-back, write-allocate) |
| `rtl/mem_bridge.v` | Arbiter + clock-domain crossing to the MIG native user interface |
| `rtl/mmio.v`, `rtl/uart.v` | Peripherals (UART with FIFOs, OLED, LEDs, switches, buttons, 7-seg, timers) |
| `rtl/top_nexys4ddr.v` | Board top level: MMCM, MIG, OLED controller, 7-segment driver |
| `vivado/build.tcl` | Creates the Vivado project, generates the MIG, builds the bitstream |
| `vivado/mig.prj`, `vivado/doom.xdc` | DDR2 controller settings and pin constraints |
| `sw/boot/` | Bootloader (runs from boot RAM, loads programs over UART) |
| `sw/doom/` | Doom port (doomgeneric + platform layer) |
| `sw/tests/` | `hello.c`, `memtest.c` bring-up programs |
| `tools/load.py` | PC-side loader: sends the program and WAD, then shows the board's output |
| `prebuilt/` | Ready-built `doom.elf`, `memtest.elf`, `hello.elf` |
| `sim/` | Testbench, MIG model, scripts |

Memory map:

| Address | |
|---|---|
| `0x0000_0000` | Boot RAM, 16 KB (bootloader; the PC starts here) |
| `0x8000_0000` | DDR2, 128 MB, cached. Programs are linked here. |
| `0xC000_0000` | Same DDR2, uncached (the bootloader writes through this) |
| `0x8400_0000` | WAD header (`'WADL'`, size); WAD data at `0x8400_0010` |
| `0xFFFF_0000` | Peripherals: offsets as in `Wrapper.v`, plus `0xA4` ms timer, `0xA8` µs timer, `0xAC` DDR ready. See `rtl/mmio.v`. |

## Bring-up on the board

You need: Vivado (with the free WebPACK licence; Artix-7 100T is included), the Nexys 4 DDR,
the Pmod OLEDrgb in **JB**, Python 3 with `pip install pyserial`, and a WAD file. Use the
shareware `doom1.wad` (4 MB, loads in about 50 s) or Freedoom's `freedoom1.wad` (29 MB, about
5.5 minutes at 921600 baud).

### 1. Build the bitstream

```
cd doom/vivado
vivado -mode batch -source build.tcl
```

This creates the project in `doom/vivado/proj`, generates the DDR2 controller from `mig.prj`,
and writes `doom/vivado/out/top_nexys4ddr.bit`. The last lines print the CPU clock and the
worst setup slack (WNS).

- **WNS negative:** timing failed. Rebuild with a slower CPU clock, e.g.
  `vivado -mode batch -source build.tcl -tclargs 25` (40 MHz). The argument is the MMCM divider:
  CPU clock = 1000 MHz / divider. 20 (50 MHz) is the default.
- **WNS comfortably positive:** you can try faster, e.g. `-tclargs 16` (62.5 MHz).
- **The MIG step fails:** see [If the MIG step fails](#if-the-mig-step-fails).

### 2. Program the board

```
vivado -mode batch -source program.tcl
```

(or Hardware Manager → Program Device → `out/top_nexys4ddr.bit`).

What you should see: the 7-segment display shows `b0070000` and LED0 is on. **LED1 turns on
when the DDR2 controller has calibrated.** If LED1 never comes on, the processor will hang on
the first DDR2 access; see Troubleshooting.

### 3. Check the memory system first

```
python3 doom/tools/load.py --port COM5 doom/prebuilt/memtest.elf
```

(Linux: `--port /dev/ttyUSB1`; on Windows, check Device Manager for the COM port of the
board's USB serial converter, usually the higher-numbered of two.)

Expected output ends with `memtest OK`. This exercises cache misses, write-backs, byte and
halfword stores, and the uncached alias against the real DDR2.

### 4. Run Doom

Press the red **CPU RESET** button (so the bootloader is waiting again), then:

```
python3 doom/tools/load.py --port COM5 doom/prebuilt/doom.elf --wad doom1.wad
```

The terminal stays open after loading: it shows Doom's console output and sends your key
presses to the game.

Controls on the board: BTNU/BTND/BTNL/BTNR move and turn (and navigate menus), BTNC fires and
selects menu items, flipping SW0 opens/closes the menu (Escape), flipping SW1 is "use" (doors,
switches). SW2 up crops the status bar so the view fills the screen; SW3 up enables smoother
downscaling. The 7-segment display shows frames per second (right two digits).

Controls in the terminal: arrows or WASD, F (fire), Space or E (use), Enter, Esc or Q (menu),
Y/N, 1–7 (weapons), Tab (map).

**Re-running without reloading:** with SW15 up, the bootloader skips loading and jumps straight
to the program already in DDR2 when you press CPU RESET.

## If the MIG step fails

`build.tcl` imports `vivado/mig.prj` non-interactively. If your Vivado version rejects that,
create the IP by hand once, then re-run the script (it will still regenerate it, so instead
continue the build in the GUI):

1. `vivado -mode batch -source build.tcl -tclargs 20 project` (creates the project, may stop at the MIG).
2. Open `doom/vivado/proj/doom_soc.xpr` in the GUI. IP Catalog → Memory Interface Generator (MIG 7 Series).
3. Component name **mig_ddr2**. Choose "Verify Pin Changes and Update Design" / import `doom/vivado/mig.prj`.
   If you have to go through the pages manually, the settings are: DDR2 SDRAM, MT47H64M16HR-25E,
   clock period 3077 ps (325 MHz), PHY ratio 4:1, input clock 200 MHz, data width 16, data mask on,
   **native interface (not AXI)**, ordering **strict**, system clock **No Buffer**, reference clock
   **Use System Clock**, system reset **active low**, XADC enabled, pinout from the `.prj`.
4. Generate, then Run Synthesis / Implementation / Generate Bitstream.

If synthesis complains about MIG ports in `rtl/top_nexys4ddr.v` (`u_mig`), compare with the
generated instantiation template (`proj/doom_soc.gen/sources_1/ip/mig_ddr2/mig_ddr2/user_design/rtl/mig_ddr2.v`
or the `.veo` file) and adjust the port list; outputs that are not listed can be left out.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Nothing on the UART | Wrong COM port, or baud rate: the bootloader uses 921600 (`--baud`). Press CPU RESET; it prints `ready`. |
| LED1 never turns on | DDR2 calibration failed: check that the MIG settings match `mig.prj` (325 MHz, 200 MHz input). |
| `memtest` fails | Memory system problem on hardware. Note the failing test and address; try a slower CPU clock. |
| Loader says "expected b'K'" | A transfer error. Try `--baud 460800` (and rebuild with `BAUD` changed in `top_nexys4ddr.v`), or a shorter USB cable. |
| OLED stays dark | Pmod in the wrong connector (must be JB, top row pins 1–6 aligned) or the OLED controller never left reset. |
| Doom prints `W_GetNumForName` / `Z_Malloc` errors | WAD not loaded or corrupted: reload with `--verify`. |

## Simulation and development

All of this runs on Linux (or WSL). Tools: `apt install iverilog verilator gcc-riscv64-unknown-elf picolibc-riscv64-unknown-elf`.

| Command | What it does |
|---|---|
| `tests/riscv-tests/run.sh` | riscv-tests on the course `Wrapper.v` system (48/48 pass) |
| `doom/sim/rvtests/run.sh [-v]` | riscv-tests on the SoC, from DDR2 through both caches (48/48 pass) |
| `doom/sw/build.sh OUT src.c` | Build a bare-metal C program linked at `0x80000000` |
| `doom/sw/boot/build.sh` | Rebuild the bootloader (`sw/boot/boot.mem`, used by synthesis) |
| `doom/sw/doom/build.sh` | Build Doom (`sw/build/doom.elf`) |
| `doom/sim/run.sh [-v] BOOT.mem DDR.mem +plusargs` | Simulate the SoC (`-v` = Verilator) |

Example: run Doom in simulation and save the OLED frames as images:

```
python3 doom/sw/common/mkimg.py --ddr doom.ddr.mem --wad freedoom1.wad doom/sw/build/doom.elf
doom/sim/run.sh -v doom/sim/stub_boot.mem doom.ddr.mem +quiet +cycles=0 +max_frames=5 +frames=frame
```

`stub_boot.mem` is a two-instruction boot image that jumps straight to DDR2, skipping the
UART loader. See the top of `sim/tb_soc.v` for all plusargs.

## Design notes and limitations

- **Pipeline stall.** A cache miss or uncached access freezes every pipeline register for that
  cycle. Stores and peripheral side effects only happen on the cycle the instruction leaves the
  Memory stage, so they happen exactly once.
- **Synchronous memories.** Instruction memory is addressed with the next PC; data memory with
  the Execute-stage address. A store followed immediately by a load of the same word is handled
  by a bypass register (block RAMs are read-first).
- **Coherence.** The cached (`0x8…`) and uncached (`0xC…`) views of DDR2 are not kept coherent.
  The bootloader writes only through the uncached view, before the program runs, so this is
  fine. The I-cache is not coherent with stores either (no self-modifying code).
- **Not supported:** misaligned loads/stores (GCC does not generate them), interrupts, CSRs,
  `fence.i`. Doom has no sound and cannot save games or settings.
- **Clocking.** CPU and peripherals share one clock from the MMCM; the MIG runs on its own
  `ui_clk`. The only crossing is in `mem_bridge.v`, constrained in `doom.xdc`.
