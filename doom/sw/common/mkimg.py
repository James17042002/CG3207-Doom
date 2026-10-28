#!/usr/bin/env python3
"""Build memory images for the doom SoC from ELF files and raw binary blobs.

  mkimg.py --boot boot.mem --ddr ddr.mem [--boot-words 4096] [--ddr-lines N] inputs...

Each input is either an ELF file (its PT_LOAD segments are placed at their physical addresses)
or FILE@ADDR for a raw binary (ADDR in hex, e.g. doom1.wad@0x84000000).
Boot RAM (0x00000000..) -> 32-bit words, one per line.
DDR2 (0x80000000.. or uncached alias 0xC0000000..) -> 128-bit lines with @line address markers,
  sparse (only lines that contain data), for $readmemh in mig_model.v.
"""
import argparse, struct, sys

def elf_segments(path):
    d = open(path, 'rb').read()
    if d[:4] != b'\x7fELF' or d[4] != 1:
        raise SystemExit(f"{path}: not a 32-bit ELF")
    e_phoff, = struct.unpack_from('<I', d, 28)
    e_phentsize, e_phnum = struct.unpack_from('<HH', d, 42)
    segs = []
    for i in range(e_phnum):
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = \
            struct.unpack_from('<8I', d, e_phoff + i * e_phentsize)
        if p_type == 1 and p_memsz:
            data = d[p_offset:p_offset + p_filesz] + b'\0' * (p_memsz - p_filesz)
            segs.append((p_paddr, data))
    return segs

def load_inputs(inputs):
    segs = []
    for item in inputs:
        if '@' in item:
            f, a = item.rsplit('@', 1)
            segs.append((int(a, 16), open(f, 'rb').read()))
        else:
            segs += elf_segments(item)
    return segs

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--boot'); ap.add_argument('--ddr')
    ap.add_argument('--boot-words', type=int, default=4096)
    ap.add_argument('inputs', nargs='+')
    a = ap.parse_args()
    boot = bytearray(a.boot_words * 4)
    ddr = {}                                   # line index -> bytearray(16)
    for addr, data in load_inputs(a.inputs):
        if addr < 0x10000:
            if addr + len(data) > len(boot): raise SystemExit("boot image too large for boot RAM")
            boot[addr:addr + len(data)] = data
        elif (addr >> 27) in (0x10, 0x18):     # 0x80000000 or 0xC0000000 region
            off = addr & 0x07FFFFFF
            for i in range(0, len(data)):
                ln = (off + i) >> 4
                if ln not in ddr: ddr[ln] = bytearray(16)
                ddr[ln][(off + i) & 15] = data[i]
        else:
            raise SystemExit(f"segment at 0x{addr:08x} is not in boot RAM or DDR2")
    if a.boot:
        with open(a.boot, 'w') as f:
            for i in range(0, len(boot), 4):
                f.write('%08x\n' % int.from_bytes(boot[i:i+4], 'little'))
    if a.ddr:
        with open(a.ddr, 'w') as f:
            prev = None
            for ln in sorted(ddr):
                if prev is None or ln != prev + 1: f.write('@%x\n' % ln)
                f.write('%032x\n' % int.from_bytes(ddr[ln], 'little'))
                prev = ln
            if not ddr: f.write('@0\n%032x\n' % 0)

if __name__ == '__main__':
    main()
