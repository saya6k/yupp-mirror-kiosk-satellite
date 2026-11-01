#!/usr/bin/env python3
"""YUPP's boot logo for the loader's second stage, as a raw framebuffer image.

  make-loader-logo.py VENDOR_BOOTANIMATION_ZIP OUT_RAW

The loader (loader/init) writes it to /dev/fb0 once the mirror's display is up
and shows it until Android's boot animation takes over, as the vendor's boot
showed it. The picture is the last frame of the vendor's own boot animation
(/system/media/bootanimation.zip in the eMMC dump, 1080x1920 portrait); YUPP's
logo is a trademark and stays out of this repository. The framebuffer is the
panel's 1920x1080 in XRGB8888 (bytes B, G, R, X), and the panel is mounted
turned, so the picture is turned a quarter counter-clockwise (checked on the mirror).
It needs Pillow.
"""
import io, sys, zipfile
from PIL import Image

W, H = 1920, 1080

vendor_zip, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(vendor_zip) as z:
    names = sorted(n for n in z.namelist() if n.endswith(".png"))
    img = Image.open(io.BytesIO(z.read(names[-1]))).convert("RGB")
img = img.transpose(Image.ROTATE_90)
assert img.size == (W, H), img.size
r, g, b = img.split()
x = Image.new("L", (W, H), 255)
open(out, "wb").write(Image.merge("RGBA", (b, g, r, x)).tobytes())
print(f"{out}: {W}x{H} XRGB8888")
