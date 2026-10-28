#!/usr/bin/env python3
"""Load a program (and optionally a Doom WAD) into the board over the UART, then run it.

  python3 load.py --port COM5 build/doom.elf --wad doom1.wad          (Windows)
  python3 load.py --port /dev/ttyUSB1 build/doom.elf --wad doom1.wad  (Linux)

Needs pyserial (pip install pyserial). Press the CPU RESET button on the board first, so the
bootloader is waiting (it prints "ready"). The WAD goes to 0x84000010 with a header at 0x84000000:
  0x84000000: 'WADL'   0x84000004: WAD size in bytes
--out FILE writes the byte stream to a file instead (used by the simulation testbench).
"""
import argparse, struct, sys, time

WAD_HDR = 0x84000000
CHUNK = 4096

def checksum(data, c=0):
    for b in data:
        c = (((c << 1) | (c >> 31)) + b) & 0xFFFFFFFF
    return c

def elf_load_segments(path):
    d = open(path, 'rb').read()
    if d[:4] != b'\x7fELF' or d[4] != 1: raise SystemExit(f"{path}: not a 32-bit ELF")
    entry, = struct.unpack_from('<I', d, 24)
    phoff, = struct.unpack_from('<I', d, 28)
    phentsize, phnum = struct.unpack_from('<HH', d, 42)
    segs = []
    for i in range(phnum):
        t, off, va, pa, fsz, msz, fl, al = struct.unpack_from('<8I', d, phoff + i * phentsize)
        if t == 1 and fsz: segs.append((pa, d[off:off + fsz]))
    return entry, segs

class Link:
    def __init__(self, port, baud, out):
        self.f = open(out, 'wb') if out else None
        if not out:
            import serial
            self.s = serial.Serial(port, baud, timeout=5)
            time.sleep(0.1); self.s.reset_input_buffer()
    def send(self, b):
        if self.f: self.f.write(b)
        else: self.s.write(b)
    def expect(self, ch, what):
        if self.f: return
        r = self.s.read(1)
        if r != ch: raise SystemExit(f"{what}: expected {ch!r}, got {r!r} (is the bootloader waiting? press CPU RESET)")
    def read32(self):
        if self.f: return None
        r = self.s.read(4)
        if len(r) != 4: raise SystemExit("timeout reading from board")
        return struct.unpack('<I', r)[0]

def write(link, addr, data, label):
    t0 = time.time()
    for o in range(0, len(data), CHUNK):
        part = data[o:o + CHUNK]
        link.send(b'W' + struct.pack('<II', addr + o, len(part)) + part + struct.pack('<I', checksum(part)))
        link.expect(b'K', f"write at 0x{addr + o:08x}")
        if not link.f and len(data) > CHUNK:
            done = o + len(part); rate = done / max(time.time() - t0, 1e-6)
            print(f"\r  {label}: {done * 100 // len(data):3d}%  {rate / 1024:6.1f} KB/s", end='', flush=True)
    if not link.f and len(data) > CHUNK: print()

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('elf'); ap.add_argument('--wad')
    ap.add_argument('--port'); ap.add_argument('--baud', type=int, default=921600)
    ap.add_argument('--out', help='write the byte stream to a file instead of a serial port')
    ap.add_argument('--no-run', action='store_true'); ap.add_argument('--verify', action='store_true')
    a = ap.parse_args()
    if not a.port and not a.out: ap.error('--port or --out is required')
    link = Link(a.port, a.baud, a.out)
    link.send(b'P'); link.expect(b'B', 'ping')
    entry, segs = elf_load_segments(a.elf)
    for addr, data in segs:
        print(f"program: {len(data)} bytes at 0x{addr:08x}")
        write(link, addr, data, 'program')
    if a.wad:
        wad = open(a.wad, 'rb').read()
        print(f"WAD: {len(wad)} bytes at 0x{WAD_HDR + 16:08x}")
        write(link, WAD_HDR, b'WADL' + struct.pack('<III', len(wad), 0, 0), 'header')
        write(link, WAD_HDR + 16, wad, 'WAD')
    if a.verify and not a.out:
        for addr, data in segs:
            link.send(b'C' + struct.pack('<II', addr, len(data)))
            got = link.read32()
            print(f"verify 0x{addr:08x}: {'ok' if got == checksum(data) else 'MISMATCH'}")
    if not a.no_run:
        link.send(b'J' + struct.pack('<I', entry)); link.expect(b'J', 'jump')
        print(f"running from 0x{entry:08x}")
        if not a.out:
            print("--- board output (Ctrl+C to quit) ---")
            try:
                while True:
                    b = link.s.read(1)
                    if b: sys.stdout.write(b.decode('latin-1')); sys.stdout.flush()
            except KeyboardInterrupt:
                pass

if __name__ == '__main__':
    main()
