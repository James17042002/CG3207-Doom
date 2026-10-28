#!/usr/bin/env bash
# Turn "+pc_every" samples from a simulation log into a function histogram.
#   doom/tools/pcprof.sh sim.log program.elf
set -euo pipefail
grep -o "PC sample [0-9a-f]*" "$1" | awk '{print "0x"$3}' > /tmp/pcprof.$$
riscv64-unknown-elf-addr2line -f -e "$2" < /tmp/pcprof.$$ | awk 'NR%2==1' | sort | uniq -c | sort -rn | head -25
rm -f /tmp/pcprof.$$
