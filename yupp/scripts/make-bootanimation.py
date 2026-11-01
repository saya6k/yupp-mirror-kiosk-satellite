#!/usr/bin/env python3
"""The mirror's boot animation: upstream's, the Kiosk Satellite mark, for its screen.

  make-bootanimation.py OUT_ZIP

Upstream's scripts/make-bootanimation.py builds it for the Echo Shows'
screen heights; this runs the same build for the mirror's 1080x1920 portrait
screen. It needs Pillow.
"""
import importlib.util, os, shutil, sys, tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
spec = importlib.util.spec_from_file_location("ks_bootanimation", os.path.join(REPO, "scripts/make-bootanimation.py"))
ks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ks)

HEIGHT = 1920

if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with tempfile.TemporaryDirectory() as d:
        ks.build(ks.MARK, HEIGHT, d)
        shutil.move(os.path.join(d, f"bootanimation-{HEIGHT}.zip"), out)
