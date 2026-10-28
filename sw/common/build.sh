#!/usr/bin/env bash
# Build a bare-metal C program for the processor: sw/common/build.sh OUT_PREFIX src.c [more.c ...]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$1"; shift
mkdir -p "$(dirname "$OUT")"
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -Os -ffreestanding -nostdlib -nostartfiles \
    -fno-pic -mno-relax -Wl,--no-relax -I"$HERE" -T "$HERE/link.ld" -Wl,-Map,"$OUT.map" \
    -o "$OUT.elf" "$HERE/crt0.S" "$@" -lgcc
riscv64-unknown-elf-objdump -d "$OUT.elf" > "$OUT.dis"
python3 "$HERE/mkmem.py" "$OUT.elf" "$OUT"
