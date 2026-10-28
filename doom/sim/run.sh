#!/usr/bin/env bash
# Simulate the doom SoC.
#   doom/sim/run.sh [-v] [-D NAME=VALUE ...] BOOT.mem DDR.mem [plusargs...]
#     -v        use Verilator (fast; needed for Doom) instead of Icarus Verilog
#     -D        override a tb_soc parameter, e.g. -D LINE_BITS=23 (DDR model size)
# The images are copied to boot.mem / ddr.mem in the build directory (doom/sim/build[-v]).
# See tb_soc.v for plusargs (+cycles=N, +uart_in=FILE, +frames=PREFIX, ...).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CORE="$ROOT/project/project.srcs/sources_1/imports"
SIM=iverilog; PARAMS=(); POS=(); PLUS=()
while [ $# -gt 0 ]; do             # options may appear anywhere
  case "$1" in
    -v) SIM=verilator; shift ;;
    -D) PARAMS+=("$2"); shift 2 ;;
    +*) PLUS+=("$1"); shift ;;
    *)  POS+=("$1"); shift ;;
  esac
done
[ ${#POS[@]} -eq 2 ] || { echo "usage: $0 [-v] [-D P=V] BOOT.mem DDR.mem [plusargs]"; exit 2; }
BOOT="$(realpath "${POS[0]}")"; DDR="$(realpath "${POS[1]}")"
set -- "${PLUS[@]:-}"

SRCS=("$HERE/tb_soc.v" "$HERE/mig_model.v" "$ROOT"/doom/rtl/{soc,rv_core,sdp_ram,icache,dcache,mem_bridge,mmio,uart}.v
      "$CORE"/Asst_02/{ALU,Decoder,Extend,PC_Logic,RegFile,Shifter}.v "$CORE"/Asst_03/MCycle.v)
TAG=$(printf '%s' "${PARAMS[*]:-}" | md5sum | cut -c1-8)
BUILD="$HERE/build-$SIM-$TAG"; mkdir -p "$BUILD"
cp "$BOOT" "$BUILD/boot.mem"; cp "$DDR" "$BUILD/ddr.mem"
cd "$BUILD"

if [ "$SIM" = iverilog ]; then
  PFLAGS=(); for p in "${PARAMS[@]:-}"; do [ -n "$p" ] && PFLAGS+=("-Ptb_soc.$p"); done
  iverilog -g2012 -o tb.vvp -s tb_soc "${PFLAGS[@]}" "${SRCS[@]}"
  exec vvp -n tb.vvp "$@"
else
  BIN="$BUILD/obj_dir/Vtb_soc"
  NEED=0; [ -x "$BIN" ] || NEED=1
  for s in "${SRCS[@]}"; do [ "$s" -nt "$BIN" ] 2>/dev/null && NEED=1; done
  if [ $NEED = 1 ]; then
    GFLAGS=(); for p in "${PARAMS[@]:-}"; do [ -n "$p" ] && GFLAGS+=("-G$p"); done
    verilator --binary --timing -O3 -j 0 -Wno-fatal -Wno-lint -Wno-style --top-module tb_soc \
        "${GFLAGS[@]}" -CFLAGS -O2 "${SRCS[@]}" > verilator.log 2>&1 || { tail -40 verilator.log; exit 1; }
  fi
  exec "$BIN" "$@"
fi
