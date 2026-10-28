#!/usr/bin/env bash
# Build the bootloader -> doom/sw/boot/boot.mem (boot RAM image, 4096 x 32-bit words).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../build/boot"; mkdir -p "$(dirname "$OUT")"
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -Os -ffreestanding -nostdlib -nostartfiles \
    -Wl,--no-warn-rwx-segments -I"$HERE/../common" -T "$HERE/link_boot.ld" \
    -o "$OUT.elf" "$HERE/crt0_boot.S" "$HERE/boot.c" -lgcc
riscv64-unknown-elf-objdump -d "$OUT.elf" > "$OUT.dis"
python3 "$HERE/../common/mkimg.py" --boot "$HERE/boot.mem" "$OUT.elf"
riscv64-unknown-elf-size "$OUT.elf"
