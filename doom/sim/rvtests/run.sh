#!/usr/bin/env bash
# Run riscv-tests (rv32ui + rv32um) on the doom SoC, from DDR2 through both caches.
#   doom/sim/rvtests/run.sh [-v] [test ...]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
V=""; [ "${1:-}" = "-v" ] && { V="-v"; shift; }
RT="${RISCV_TESTS:-$ROOT/../ext/riscv-tests}"
[ -d "$RT/isa" ] || git clone -q --depth 1 https://github.com/riscv-software-src/riscv-tests "$RT"
OUT="$HERE/build"; mkdir -p "$OUT"
SKIP=" fence_i ma_data "
if [ $# -gt 0 ]; then TESTS="$*"; else
  TESTS=$(for f in "$RT"/isa/rv32ui/*.S "$RT"/isa/rv32um/*.S; do basename "$f" .S; done); fi
pass=0; fail=0; failed=""
for t in $TESTS; do
  [[ "$SKIP" == *" $t "* ]] && continue
  src=$(ls "$RT"/isa/rv32ui/$t.S "$RT"/isa/rv32um/$t.S 2>/dev/null | head -1)
  riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles -T "$HERE/link.ld" \
      -I"$ROOT/tests/riscv-tests/env" -I"$RT/isa/macros/scalar" -o "$OUT/$t.elf" "$src" \
      || { fail=$((fail+1)); failed="$failed $t(build)"; continue; }
  python3 "$ROOT/doom/sw/common/mkimg.py" --ddr "$OUT/$t.ddr.mem" "$OUT/$t.elf"
  res=$("$ROOT/doom/sim/run.sh" $V "$ROOT/doom/sim/stub_boot.mem" "$OUT/$t.ddr.mem" +quiet +cycles=200000 2>&1 \
        | grep -E "^SIM (PASS|FAIL|TIMEOUT)")
  if [[ "$res" == "SIM PASS"* ]]; then pass=$((pass+1)); printf "  %-8s PASS  (%s)\n" "$t" "${res#SIM PASS after }"
  else fail=$((fail+1)); failed="$failed $t"; printf "  %-8s %s\n" "$t" "$res"; fi
done
echo "riscv-tests on SoC: $pass passed, $fail failed${failed:+ ($failed )}"
[ $fail -eq 0 ]
