#!/usr/bin/env bash
# Lint the board top level (Xilinx primitives, MIG and the VHDL OLED controller are stubbed).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../../.." && pwd)"; C="$R/project/project.srcs/sources_1/imports"
verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL -Wno-SYNCASYNCNET \
  --top-module top_nexys4ddr "$HERE/stubs.v" "$R"/doom/rtl/{top_nexys4ddr,soc,rv_core,muldiv,sdp_ram,icache,dcache,mem_bridge,mmio,uart}.v \
  "$C"/Asst_02/{ALU,Decoder,Extend,PC_Logic,RegFile,Shifter}.v "$C"/Asst_03/MCycle.v 2>&1 | grep "^%" | grep "doom/rtl" || echo "doom/rtl: lint clean"
