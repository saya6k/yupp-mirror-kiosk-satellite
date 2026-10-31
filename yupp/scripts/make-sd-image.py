#!/usr/bin/env python3
"""Makes the mirror's first-boot SD image from Radxa's Rock Pi 4B Android 11
GPT image: the mirror's own idbloader (DRAM init and miniloader, sectors
64-4095 of its eMMC, with its backup copies) in place of the Rock Pi's, and
the boot partition replaced. Everything else, the GPT included, is Radxa's.

With SYSTEM.img, that ext4 image (the same size) replaces the system
partition inside super.

usage: make-sd-image.py RADXA.img VENDOR_HEADER_2M.img BOOT.img OUT.img [SYSTEM.img]
"""
import shutil, struct, sys

radxa, header, boot, out = sys.argv[1:5]
system = sys.argv[5] if len(sys.argv) > 5 else None


# The byte offset and size of a logical partition in super, from its
# primary LP metadata (linear extents only).
def lp_partition(f, super_start, wanted):
    base = super_start * 512
    f.seek(base + 4096); assert struct.unpack('<I', f.read(4))[0] == 0x616c4467
    f.seek(base + 3 * 4096); h = f.read(256)
    assert struct.unpack('<I', h[:4])[0] == 0x414C5030
    hsize = struct.unpack('<I', h[8:12])[0]
    tables = struct.unpack('<I', h[44:48])[0]
    descs = [struct.unpack('<III', h[80 + 12 * i:92 + 12 * i]) for i in range(2)]
    f.seek(base + 3 * 4096 + hsize); t = f.read(tables)
    (po, pn, ps), (eo, en, es) = descs
    for i in range(pn):
        p = t[po + i * ps:po + (i + 1) * ps]
        if p[:36].rstrip(b'\0').decode() != wanted: continue
        fe, ne = struct.unpack('<II', p[40:48])
        assert ne == 1, '%s has %d extents' % (wanted, ne)
        nsec, ttype, tdata, _ = struct.unpack('<QIQI', t[eo + fe * es:eo + fe * es + 24])
        assert ttype == 0
        return base + tdata * 512, nsec * 512
    raise SystemExit('no %s in super' % wanted)

def gpt_partition(img, wanted):
    with open(img, 'rb') as f:
        f.seek(512); h = f.read(92)
        lba, n, sz = struct.unpack('<QII', h[72:88])
        f.seek(lba * 512)
        for _ in range(n):
            e = f.read(sz)
            name = e[56:128].decode('utf-16-le').rstrip('\0')
            first, last = struct.unpack('<QQ', e[32:48])
            if name == wanted: return first, last - first + 1
    raise SystemExit('no %s partition' % wanted)

shutil.copyfile(radxa, out)
idb = open(header, 'rb').read()[64 * 512:4096 * 512]
first, count = gpt_partition(out, 'boot')
b = open(boot, 'rb').read()
assert len(b) <= count * 512, 'boot image larger than the partition'
with open(out, 'r+b') as f:
    f.seek(64 * 512); f.write(idb)
    f.seek(first * 512); f.write(b + b'\0' * (count * 512 - len(b)))
    if system:
        off, size = lp_partition(f, gpt_partition(out, 'super')[0], 'system')
        s = open(system, 'rb').read()
        assert len(s) == size, 'system image is %d bytes, the partition %d' % (len(s), size)
        f.seek(off); f.write(s)
        print('system replaced at byte %d (%d bytes)' % (off, size))
print('%s: idbloader from %s, boot at sector %d (%d of %d bytes)' % (out, header, first, len(b), count * 512))
