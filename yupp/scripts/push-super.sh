#!/bin/bash
# Writes out/NAME-yupp.img into the running mirror's super over adb, for
# each NAME given (system, system_ext, product, vendor), and reboots:
#
#   push-super.sh [-s SERIAL] NAME...
#
# Only the MiB that differ go over: the mirror hashes each MiB of its
# partitions and the Mac sends the ones that differ. On the mirror, a script
# writes them, checks every partition whole against the image's md5, and only
# then reboots, so a dropped connection leaves nothing half done. The
# partitions' places in super come from its LP metadata. The partitions are
# mounted while this writes, read-only, so the reboot follows right away.
set -euo pipefail
WORK="${YUPP_WORK:-/Volumes/koa-build/yupp}"
ADB=(adb)
[ "${1:-}" = -s ] && { ADB=(adb -s "$2"); shift 2; }
[ $# -gt 0 ] || { echo "usage: $0 [-s SERIAL] NAME..." >&2; exit 2; }
"${ADB[@]}" root >/dev/null; sleep 3; "${ADB[@]}" wait-for-device
T=/data/local/tmp/push-super
W="$WORK/out/push-super"
rm -rf "$W"; mkdir -p "$W"
"${ADB[@]}" shell "mkdir -p $T; rm -f $T/*"
"${ADB[@]}" exec-out 'dd if=/dev/block/by-name/super bs=1048576 count=1 2>/dev/null' >"$W/super-head.bin"

# NAME OFFSET_MIB SIZE, for each partition asked, from the LP metadata.
python3 -I - "$W/super-head.bin" "$WORK/out" "$@" >"$W/parts.txt" <<'PY'
import os, struct, sys
head, out, names = sys.argv[1], sys.argv[2], sys.argv[3:]
f = open(head, 'rb')
f.seek(4096); assert struct.unpack('<I', f.read(4))[0] == 0x616c4467, 'no LP geometry'
f.seek(3 * 4096); h = f.read(256)
assert struct.unpack('<I', h[:4])[0] == 0x414C5030, 'no LP header'
hsize = struct.unpack('<I', h[8:12])[0]; tables = struct.unpack('<I', h[44:48])[0]
(po, pn, ps), (eo, en, es) = [struct.unpack('<III', h[80 + 12 * i:92 + 12 * i]) for i in range(2)]
f.seek(3 * 4096 + hsize); t = f.read(tables)
parts = {}
for i in range(pn):
    p = t[po + i * ps:po + (i + 1) * ps]
    fe, ne = struct.unpack('<II', p[40:48])
    ext = [struct.unpack('<QIQI', t[eo + (fe + j) * es:eo + (fe + j) * es + 24]) for j in range(ne)]
    parts[p[:36].rstrip(b'\0').decode()] = ext
for n in names:
    ext = parts[n]
    assert len(ext) == 1 and ext[0][1] == 0, '%s is not one linear extent' % n
    off, size = ext[0][2] * 512, ext[0][0] * 512
    assert off % (1 << 20) == 0, '%s does not start on a MiB' % n
    img = os.path.join(out, n + '-yupp.img')
    assert os.path.getsize(img) == size, '%s is %d bytes, the partition %d' % (img, os.path.getsize(img), size)
    print(n, off >> 20, size)
PY
cat "$W/parts.txt"

cat >"$W/hash.sh" <<'EOF'
# hash.sh OFF_MIB COUNT: md5 of each MiB of super from OFF_MIB.
i=0
while [ $i -lt $2 ]; do
    dd if=/dev/block/by-name/super bs=1048576 skip=$(($1 + i)) count=1 2>/dev/null | md5sum | cut -d' ' -f1
    i=$((i + 1))
done
EOF
"${ADB[@]}" push "$W/hash.sh" $T/ >/dev/null

{
    echo "# Writes the changed MiB, checks each partition whole, then reboots."
    echo "cd $T; exec >apply.log 2>&1; S=/dev/block/by-name/super"
    # toybox dd truncates its output unless told not to, which a block device refuses.
    echo 'w() { dd if=$1.bin of=$S bs=1048576 skip=$2 seek=$3 count=1 conv=notrunc,fsync 2>/dev/null || { echo "$1: write at $3 failed"; exit 1; }; }'
    echo 'check() { [ "$(dd if=$S bs=4096 skip=$(($2 * 256)) count=$3 2>/dev/null | md5sum | cut -d" " -f1)" = $4 ] && echo "$1 ok" || { echo "$1 differs"; exit 1; }; }'
} >"$W/apply.sh"
checks=()
while read -r name off size; do
    chunks=$(( (size + 1048575) / 1048576 ))
    "${ADB[@]}" shell -n "sh $T/hash.sh $off $chunks" | tr -d '\r' >"$W/$name.dev.md5"
    got=$(wc -l <"$W/$name.dev.md5" | tr -d ' ')
    [ "$got" = "$chunks" ] || { echo "$name: $got of $chunks hashes came back (adb dropped?)" >&2; exit 1; }
    python3 -I - "$WORK/out/$name-yupp.img" "$W/$name.dev.md5" "$W/$name.bin" "$name" "$off" >>"$W/apply.sh" <<'PY'
import hashlib, sys
img, dev, out, name, off = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
dev = open(dev).read().split()
M = 1 << 20
k = 0
with open(img, 'rb') as f, open(out, 'wb') as o:
    i = 0
    while True:
        c = f.read(M)
        if not c: break
        # A short last MiB hashes differently on the mirror, where super
        # goes on past it, so it always goes.
        if len(c) < M or hashlib.md5(c).hexdigest() != dev[i]:
            o.write(c); print('w %s %d %d' % (name, k, off + i)); k += 1
        i += 1
print('echo "%s: %d MiB written"' % (name, k), file=sys.stdout)
print('%s: %d of %d MiB differ' % (name, k, i), file=sys.stderr)
PY
    checks+=("check $name $off $((size / 4096)) $(md5 -q "$WORK/out/$name-yupp.img")")
done <"$W/parts.txt"
{
    echo sync
    printf '%s\n' "${checks[@]}"
    echo 'echo rebooting; sync; reboot'
} >>"$W/apply.sh"

for f in "$W"/*.bin; do [ "$f" = "$W/super-head.bin" ] || "${ADB[@]}" push "$f" $T/ >/dev/null; done
"${ADB[@]}" push "$W/apply.sh" $T/ >/dev/null
"${ADB[@]}" shell "nohup sh $T/apply.sh >/dev/null 2>&1 &"
echo "$(date +%T) writing; the mirror reboots once every partition checks out ($T/apply.log)"
