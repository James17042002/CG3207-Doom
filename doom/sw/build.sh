#!/usr/bin/env bash
# Build a bare-metal program that runs from DDR2:  doom/sw/build.sh OUT src.c [more sources...]
# Produces OUT.elf, OUT.dis and OUT.ddr.mem (for simulation).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$1"; shift
mkdir -p "$(dirname "$OUT")"
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -O2 -ffreestanding -nostdlib -nostartfiles -Wl,--no-warn-rwx-segments \
    -I"$HERE/common" -T "$HERE/common/link_ddr.ld" -o "$OUT.elf" "$HERE/common/crt0.S" "$@" -lgcc
riscv64-unknown-elf-objdump -d "$OUT.elf" > "$OUT.dis"
python3 "$HERE/common/mkimg.py" --ddr "$OUT.ddr.mem" "$OUT.elf"
