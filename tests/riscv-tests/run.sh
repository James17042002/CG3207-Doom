#!/usr/bin/env bash
# Run the official riscv-tests (rv32ui + rv32um) on the core in simulation.
#   tests/riscv-tests/run.sh [test-name ...]      e.g. run.sh add mulhsu
# Needs a riscv-tests checkout in $RISCV_TESTS (default: ../ext/riscv-tests next to the repo).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$ROOT/tests/riscv-tests"
RT="${RISCV_TESTS:-$ROOT/../ext/riscv-tests}"
[ -d "$RT/isa" ] || git clone -q --depth 1 https://github.com/riscv-software-src/riscv-tests "$RT"
OUT="$HERE/build"; mkdir -p "$OUT"
# Skipped: fence_i (self-modifying code; separate instruction memory), ma_data (misaligned access)
SKIP=" fence_i ma_data "
if [ $# -gt 0 ]; then TESTS="$*"; else
  TESTS=$(for f in "$RT"/isa/rv32ui/*.S "$RT"/isa/rv32um/*.S; do basename "$f" .S; done)
fi
pass=0; fail=0; failed=""
for t in $TESTS; do
  [[ "$SKIP" == *" $t "* ]] && continue
  src=$(ls "$RT"/isa/rv32ui/$t.S "$RT"/isa/rv32um/$t.S 2>/dev/null | head -1)
  riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles -T "$HERE/link.ld" \
      -I"$HERE/env" -I"$RT/isa/macros/scalar" -o "$OUT/$t.elf" "$src" || { fail=$((fail+1)); failed="$failed $t(build)"; continue; }
  python3 "$ROOT/sw/common/mkmem.py" "$OUT/$t.elf" "$OUT/$t" > /dev/null
  res=$(SIM_DEFINES=-DSIM_MEM_DEPTH_BITS=14 "$ROOT/sim/run.sh" "$OUT/$t.irom.mem" "$OUT/$t.dmem.mem" +quiet +cycles=100000 2>&1 | grep -E "^SIM (PASS|FAIL|TIMEOUT)")
  if [[ "$res" == "SIM PASS"* ]]; then pass=$((pass+1)); printf "  %-8s PASS\n" "$t"
  else fail=$((fail+1)); failed="$failed $t"; printf "  %-8s %s\n" "$t" "$res"; fi
done
echo "riscv-tests: $pass passed, $fail failed${failed:+ ($failed )}"
[ $fail -eq 0 ]
