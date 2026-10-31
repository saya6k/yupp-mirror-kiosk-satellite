#!/usr/bin/env python3
"""Repacks a Rockchip Android boot image (header v2) with another kernel and
device tree.

Radxa's boot image carries the tree twice: in the header's dtb section and as
rk-kernel.dtb in the Rockchip resource image in the second section. Both are
replaced. The ramdisk and the resource's other files (logos) stay. The
header id is recomputed the way mkbootimg does (SHA-1 over each section and
its size).

usage: repack-boot.py BOOT.img KERNEL_IMAGE DTB OUT.img [--drop-battery]

--drop-battery leaves the charging animation (battery_*.bmp) out of the
resource image, so a larger tree keeps it no larger than Radxa's.
--ramdisk=FILE puts FILE in place of Android's ramdisk (diag/init).
--cmdline-append=TEXT adds TEXT to the header's kernel command line.
--resource-dtb=FILE puts FILE as the resource's rk-kernel.dtb instead of DTB,
which then goes in the header's dtb section only (to tell which of the two
Rockchip's U-Boot uses for itself and which it hands the kernel).
"""
import hashlib
import struct
import sys

PAGE_FIELDS = '<9I'


def pad(data, size):
    return data + b'\0' * (-len(data) % size)


def read_resource(sec):
    assert sec[:4] == b'RSCE', 'second is not a Rockchip resource image'
    hb, eb = sec[8], sec[10]
    n = struct.unpack('<I', sec[12:16])[0]
    files = []
    for i in range(n):
        e = sec[(hb + i * eb) * 512:(hb + i * eb + eb) * 512]
        assert e[:4] == b'ENTR'
        name = e[4:260].split(b'\0')[0].decode()
        off, size = struct.unpack('<II', e[260:268])
        files.append((name, e, sec[off * 512:off * 512 + size]))
    return sec[:hb * 512], hb, eb, files


# Each entry keeps its own bytes (Radxa's carry leftovers after the name);
# only the offset and size are rewritten.
def write_resource(header, hb, eb, files):
    table, blobs = b'', b''
    block = hb + eb * len(files)
    for name, entry, data in files:
        entry = bytearray(entry)
        entry[260:268] = struct.pack('<II', block + len(blobs) // 512, len(data))
        table += bytes(entry)
        blobs += pad(data, 512)
    return header + table + blobs


def main(boot_path, kernel_path, dtb_path, out_path, *opts):
    b = open(boot_path, 'rb').read()
    assert b[:8] == b'ANDROID!'
    ks, ka, rs, ra, ss, sa, ta, ps, hv = struct.unpack(PAGE_FIELDS, b[8:44])
    assert hv == 2, 'header version %d' % hv
    rec_size = struct.unpack('<I', b[1632:1636])[0]
    dtb_size = struct.unpack('<I', b[1648:1652])[0]
    r = lambda n: (n + ps - 1) // ps * ps

    off = ps
    ramdisk = b[off + r(ks):off + r(ks) + rs]
    off += r(ks) + r(rs)
    second = b[off:off + ss]
    off += r(ss)
    recovery_dtbo = b[off:off + rec_size]

    for o in opts:
        if o.startswith('--ramdisk='):
            ramdisk = open(o.split('=', 1)[1], 'rb').read()
    kernel = open(kernel_path, 'rb').read()
    dtb = open(dtb_path, 'rb').read()
    assert dtb[:4] == b'\xd0\x0d\xfe\xed', 'not a DTB'

    header, hb, eb, files = read_resource(second)
    assert 'rk-kernel.dtb' in [n for n, _, _ in files]
    res_dtb = dtb
    for o in opts:
        if o.startswith('--resource-dtb='):
            res_dtb = open(o.split('=', 1)[1], 'rb').read()
    files = [(n, e, res_dtb if n == 'rk-kernel.dtb' else d) for n, e, d in files]
    if '--drop-battery' in opts:
        files = [f for f in files if not f[0].startswith('battery_')]
    header = bytearray(header)
    header[12:16] = struct.pack('<I', len(files))
    second = write_resource(bytes(header), hb, eb, files)

    sections = (kernel, ramdisk, second, recovery_dtbo, dtb)
    h = hashlib.sha1()
    for s in sections:
        h.update(s)
        h.update(struct.pack('<I', len(s)))

    hdr = bytearray(b[:ps])
    hdr[8:12] = struct.pack('<I', len(kernel))
    hdr[16:20] = struct.pack('<I', len(ramdisk))
    hdr[24:28] = struct.pack('<I', len(second))
    hdr[576:608] = h.digest() + b'\0' * 12
    hdr[1632:1636] = struct.pack('<I', len(recovery_dtbo))
    hdr[1648:1652] = struct.pack('<I', len(dtb))
    for o in opts:
        if o.startswith('--cmdline-append='):
            cmdline = bytes(hdr[64:576]).split(b'\0')[0] + b' ' + o.split('=', 1)[1].encode()
            assert len(cmdline) < 512, 'command line longer than the header field'
            hdr[64:576] = cmdline + b'\0' * (512 - len(cmdline))

    out = bytes(hdr) + b''.join(pad(s, ps) for s in sections)
    open(out_path, 'wb').write(out)
    print('%s: %d bytes, kernel %d, ramdisk %d, second %d, dtb %d (was %d)'
          % (out_path, len(out), len(kernel), len(ramdisk), len(second), len(dtb), dtb_size))


if __name__ == '__main__':
    main(*sys.argv[1:])
