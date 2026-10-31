#!/bin/bash
# Compiles dts/rk3399-yupp-android.dts against Radxa's decompiled Rock Pi 4B
# tree into $WORK/out/rk3399-yupp-android.dtb, then flattens it next to the
# result for review. Runs dtc in a throwaway Alpine container.
set -euo pipefail
WORK="${YUPP_WORK:-/Volumes/koa-build/yupp}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$WORK/out/dts"
cp "$HERE/dts/rk3399-yupp-android.dts" "$WORK/out/dts/"
cp "$WORK/radxa-rock4b-a11/rockpi4b.dts" "$WORK/out/dts/"
cat >"$WORK/out/dts/run.sh" <<'IN'
apk add -q dtc >/dev/null
cd /w/out/dts
dtc -I dts -O dtb -o ../rk3399-yupp-android.dtb rk3399-yupp-android.dts >/tmp/dtc.log 2>&1 || { grep -v -i warning /tmp/dtc.log; exit 1; }
ls -l ../rk3399-yupp-android.dtb
IN
container run --rm -c 1 -m 512M --mount type=bind,source="$WORK",target=/w alpine:3.22 sh /w/out/dts/run.sh 2>&1 | grep -v "^\["
python3 -I "$HERE/scripts/fdtflat.py" "$WORK/out/rk3399-yupp-android.dtb" >"$WORK/out/rk3399-yupp-android.flat.txt"
