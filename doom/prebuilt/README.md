Ready-built programs for the board (load with `doom/tools/load.py`). Rebuild with:

- `doom.elf`: `doom/sw/doom/build.sh` (doomgeneric, GPL-2.0: source via `doom/sw/doom/fetch.sh`)
- `memtest.elf`, `hello.elf`: `doom/sw/build.sh doom/sw/build/memtest doom/sw/tests/memtest.c`

The bootloader is not here: it is built into the bitstream from `doom/sw/boot/boot.mem`.
