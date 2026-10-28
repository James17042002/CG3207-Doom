#!/usr/bin/env python3
"""Turn an ELF into AA_IROM.mem / AA_DMEM.mem style hex files (one 32-bit word per line)."""
import subprocess, sys, tempfile, os
elf, out_prefix = sys.argv[1], sys.argv[2]
objcopy = "riscv64-unknown-elf-objcopy"
for sec, suffix in ((".text", "irom"), (".data", "dmem")):
    with tempfile.NamedTemporaryFile(delete=False) as t: path = t.name
    subprocess.run([objcopy, "-O", "binary", "-j", sec, elf, path], check=True)
    data = open(path, "rb").read(); os.unlink(path)
    data += b"\0" * (-len(data) % 4)
    with open(f"{out_prefix}.{suffix}.mem", "w") as f:
        for i in range(0, len(data), 4):
            f.write("%08x\n" % int.from_bytes(data[i:i+4], "little"))
    print(f"{sec}: {len(data)} bytes -> {out_prefix}.{suffix}.mem")
