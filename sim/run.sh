#!/usr/bin/env bash
# Run a program on the Wrapper + RV design in Icarus Verilog.
#
#   sim/run.sh IROM.mem [DMEM.mem] [plusargs...]
#
# Example: sim/run.sh build/test.irom.mem build/test.dmem.mem +cycles=50000 +quiet
# The RTL is taken from the live Vivado sources (project/project.srcs/sources_1/imports).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/project/project.srcs/sources_1/imports"
BUILD="$ROOT/sim/build"

[ $# -ge 1 ] || { echo "usage: $0 IROM.mem [DMEM.mem] [plusargs...]"; exit 2; }
IROM="$(realpath "$1")"; shift
DMEM=""
if [ $# -ge 1 ] && [[ "$1" != +* ]]; then DMEM="$(realpath "$1")"; shift; fi

mkdir -p "$BUILD"
cd "$BUILD"
# Wrapper.v reads AA_IROM.mem / AA_DMEM.mem from the current directory.
cp "$IROM" AA_IROM.mem
if [ -n "$DMEM" ]; then cp "$DMEM" AA_DMEM.mem; else : > AA_DMEM.mem; fi

iverilog -g2012 -o tb.vvp -s tb_wrapper \
    "$ROOT/sim/tb_wrapper.v" \
    "$SRC"/Asst_02/{Wrapper,RV,ALU,Decoder,Extend,PC_Logic,ProgramCounter,RegFile,Shifter}.v \
    "$SRC"/Asst_03/MCycle.v
vvp -n tb.vvp "$@"
