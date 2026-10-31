#!/bin/bash
# Adds the remote access files (remote/) to a copy of Radxa's system image:
#   /adb_keys                          this Mac's adb key
#   /system/etc/init/yupp-remote.rc    adb on Wi-Fi, starts the script
#   /system/etc/yupp-remote.sh         joins the mirror's Wi-Fi
# The Wi-Fi name and passphrase come from the Armbian board's
# wpa_supplicant-wlan0.conf; the filled-in script stays on the build SSD.
set -euo pipefail
WORK="${YUPP_WORK:-/Volumes/koa-build/yupp}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${YUPP_WPA_CONF:-$HOME/Projects/armbian-yupp-aiot3399x/packages/bsp/yupp-aiot3399x/wpa_supplicant-wlan0.conf}"
IN="$WORK/out/system-in"
mkdir -p "$IN"

# The conf keeps only the hashed PSK, and Android's cmd wifi takes the
# passphrase, so it comes from YUPP_WIFI_PASSPHRASE and must hash to the
# conf's PSK.
: "${YUPP_WIFI_PASSPHRASE:?set YUPP_WIFI_PASSPHRASE to the passphrase of the mirror network}"
python3 -I - "$CONF" "$HERE/remote/yupp-remote.sh.in" "$IN/yupp-remote.sh" <<'EOF'
import hashlib, os, re, sys
conf = open(sys.argv[1]).read()
block = re.search(r'^network=\{(.*?)^\}', conf, re.S | re.M).group(1)
ssid = re.search(r'^\s*ssid="([^"]*)"', block, re.M).group(1)
psk = re.search(r'^\s*psk=([0-9a-fA-F]{64})\s*$', block, re.M).group(1).lower()
passphrase = os.environ['YUPP_WIFI_PASSPHRASE']
assert hashlib.pbkdf2_hmac('sha1', passphrase.encode(), ssid.encode(), 4096, 32).hex() == psk, \
    'YUPP_WIFI_PASSPHRASE does not match the PSK in ' + sys.argv[1]
assert "'" not in ssid + passphrase, 'quote in the Wi-Fi name or passphrase'
open(sys.argv[3], 'w').write(open(sys.argv[2]).read().replace('@SSID@', ssid).replace('@PSK@', passphrase))
print('Wi-Fi:', ssid)
EOF
cp "$HERE/remote/yupp-remote.rc" "$IN/"
cp "$HOME/.android/adbkey.pub" "$IN/adb_keys"
cp "$WORK/radxa-rock4b-a11/parts/system.img" "$WORK/out/system-yupp.img"

cat >"$IN/run.sh" <<'IN'
set -e
apk add -q e2fsprogs e2fsprogs-extra >/dev/null
img=/w/out/system-yupp.img
label() { printf '%s\0' "$1" >/tmp/l; }
label u:object_r:system_file:s0; cp /tmp/l /tmp/system_file
label u:object_r:adb_keys_file:s0; cp /tmp/l /tmp/adb_keys_file
debugfs -w "$img" <<CMDS >/dev/null
cd /system/etc/init
write /w/out/system-in/yupp-remote.rc yupp-remote.rc
sif yupp-remote.rc mode 0100644
sif yupp-remote.rc uid 0
sif yupp-remote.rc gid 0
ea_set -f /tmp/system_file yupp-remote.rc security.selinux
cd /system/etc
write /w/out/system-in/yupp-remote.sh yupp-remote.sh
sif yupp-remote.sh mode 0100755
sif yupp-remote.sh uid 0
sif yupp-remote.sh gid 2000
ea_set -f /tmp/system_file yupp-remote.sh security.selinux
cd /
write /w/out/system-in/adb_keys adb_keys
sif adb_keys mode 0100644
sif adb_keys uid 0
sif adb_keys gid 0
ea_set -f /tmp/adb_keys_file adb_keys security.selinux
CMDS
for f in /adb_keys /system/etc/init/yupp-remote.rc /system/etc/yupp-remote.sh /system/etc/init/vold.rc; do
  printf '%s ' "$f"; debugfs -R "stat $f" "$img" 2>/dev/null | grep -o -E "Mode: +[0-7]+|User: +[0-9]+ +Group: +[0-9]+|Size: [0-9]+" | tr '\n' ' '
  debugfs -R "ea_get $f security.selinux" "$img" 2>/dev/null | tr -d '\n'; echo
done
e2fsck -fn "$img" 2>&1 | tail -3
IN
container run --rm -c 1 -m 1G --mount type=bind,source="$WORK",target=/w alpine:3.22 sh /w/out/system-in/run.sh 2>&1 | grep -v "^\["
