#!/usr/bin/env bash
# Build Doom for the doom SoC -> doom/sw/build/doom.elf
#   doom/sw/doom/build.sh            (fetches doomgeneric on first use)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SW="$HERE/.."
OUT="$SW/build/doom"; OBJ="$SW/build/doom-obj"; mkdir -p "$OBJ"
[ -d "$HERE/doomgeneric/doomgeneric" ] || "$HERE/fetch.sh"
DG="$HERE/doomgeneric/doomgeneric"

CFLAGS=(-march=rv32im -mabi=ilp32 --specs=picolibc.specs -O2 -g -ffunction-sections -fdata-sections
        -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200 -DCMAP256 -DNORMALUNIX -D_DEFAULT_SOURCE
        -I"$DG" -I"$SW/common" -w)
SRCS="dummy am_map doomdef doomstat dstrings d_event d_items d_iwad d_loop d_main d_mode d_net f_finale f_wipe
      g_game hu_lib hu_stuff info i_cdmus i_endoom i_joystick i_scale i_sound i_system i_timer memio m_argv
      m_bbox m_cheat m_config m_controls m_fixed m_menu m_misc m_random p_ceilng p_doors p_enemy p_floor
      p_inter p_lights p_map p_maputl p_mobj p_plats p_pspr p_saveg p_setup p_sight p_spec p_switch
      p_telept p_tick p_user r_bsp r_data r_draw r_main r_plane r_segs r_sky r_things sha1 sounds statdump
      st_lib st_stuff s_sound tables v_video wi_stuff w_checksum w_file w_main w_wad z_zone
      i_input i_video doomgeneric"
# i_video.c: skip the per-frame copy into DG_ScreenBuffer when it is the same buffer
# (doomgeneric_cg3207.c points DG_ScreenBuffer at I_VideoBuffer).
sed 's/memcpy(line_out, line_in, SCREENWIDTH);/if (line_out != line_in) memcpy(line_out, line_in, SCREENWIDTH);/' \
    "$DG/i_video.c" > "$OBJ/i_video_patched.c"
OBJS=()
for s in $SRCS; do
  o="$OBJ/$s.o"; OBJS+=("$o")
  src="$DG/$s.c"; [ "$s" = i_video ] && src="$OBJ/i_video_patched.c"
  if [ ! -f "$o" ] || [ "$src" -nt "$o" ]; then
    riscv64-unknown-elf-gcc "${CFLAGS[@]}" -c "$src" -o "$o" &
    while [ "$(jobs -r | wc -l)" -ge "$(nproc)" ]; do wait -n; done
  fi
done
wait
for s in doomgeneric_cg3207 syscalls w_file_mem; do
  riscv64-unknown-elf-gcc "${CFLAGS[@]}" -Wall -c "$HERE/$s.c" -o "$OBJ/$s.o"; OBJS+=("$OBJ/$s.o")
done
riscv64-unknown-elf-gcc "${CFLAGS[@]}" -nostartfiles -T "$SW/common/link_ddr.ld" -Wl,--gc-sections \
    -Wl,--no-warn-rwx-segments -Wl,-Map,"$OUT.map" -o "$OUT.elf" "$SW/common/crt0.S" "${OBJS[@]}" -lm -lgcc
riscv64-unknown-elf-size "$OUT.elf"
