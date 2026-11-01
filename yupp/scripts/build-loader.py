#!/usr/bin/env python3
"""Puts loader/init (and files beside it) into a loader boot image.

  build-loader.py BOOT.img OUT.img [NAME=FILE ...]

BOOT.img is a loader boot image already on the mirror (read back from its boot
partition): its ramdisk holds the loader with kexec-tools in /kx, the mirror's
tree as /yupp.dtb and Android's ramdisk as /android-ramdisk.img. This replaces
/init with loader/init and puts each FILE in the ramdisk root as NAME
(replacing one of that name), then repacks the image with repack-boot.py,
which keeps the kernel, trees, command line and resource as they are.
"""
import gzip, os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def entries(c):
    i = 0
    while True:
        h = c[i:i + 110]
        assert h[:6] == b"070701", "not a newc archive"
        f = [int(h[6 + 8 * k:14 + 8 * k], 16) for k in range(13)]
        nsz, fsz = f[11], f[6]
        name = c[i + 110:i + 110 + nsz - 1]
        ns = i + 110 + nsz; ns += -ns % 4
        nx = ns + fsz; nx += -nx % 4
        yield name, f, c[ns:ns + fsz], c[i:nx]
        i = nx
        if name == b"TRAILER!!!":
            return


def entry(name, fields, data):
    fields = list(fields); fields[6] = len(data); fields[11] = len(name) + 1
    e = b"070701" + b"".join(b"%08X" % v for v in fields) + name + b"\0"
    e += b"\0" * (-len(e) % 4) + data
    return e + b"\0" * (-len(e) % 4)


def main(boot, out, *extra):
    b = open(boot, "rb").read()
    ks, _, rs = struct.unpack("<3I", b[8:20])
    pg = struct.unpack("<I", b[36:40])[0]
    off = pg + -(-ks // pg) * pg
    kernel, rd = b[pg:pg + ks], gzip.decompress(b[off:off + rs])
    dsz = struct.unpack("<I", b[1648:1652])[0]
    adds = {b"init": open(os.path.join(HERE, "loader/init"), "rb").read()}
    for a in extra:
        n, f = a.split("=", 1)
        adds[n.encode()] = open(f, "rb").read()
    new, template = b"", None
    for name, f, data, raw in entries(rd):
        if name == b"init":
            template = f
        if name in adds:
            continue
        if name == b"TRAILER!!!":
            for n, d in adds.items():
                new += entry(n, template, d)
        new += raw
    with tempfile.TemporaryDirectory() as t:
        # The header's tree follows kernel, ramdisk, second and recovery dtbo;
        # repack-boot.py takes it as a file.
        sec = pg + -(-ks // pg) * pg + -(-rs // pg) * pg
        ss = struct.unpack("<I", b[24:28])[0]
        sec += -(-ss // pg) * pg
        rdo = struct.unpack("<I", b[1632:1636])[0]
        sec += -(-rdo // pg) * pg
        dtb = b[sec:sec + dsz]
        assert dtb[:4] == b"\xd0\x0d\xfe\xed", "no tree where the header says"
        for n, d in (("Image", kernel), ("header.dtb", dtb), ("rd.cpio.gz", gzip.compress(new, 6))):
            open(os.path.join(t, n), "wb").write(d)
        base = os.path.join(t, "base.img")
        open(base, "wb").write(b[:sec + -(-dsz // pg) * pg])
        subprocess.run([sys.executable, "-I", os.path.join(HERE, "scripts/repack-boot.py"), base,
                        os.path.join(t, "Image"), os.path.join(t, "header.dtb"), out,
                        "--ramdisk=" + os.path.join(t, "rd.cpio.gz")], check=True)


if __name__ == "__main__":
    main(*sys.argv[1:])
