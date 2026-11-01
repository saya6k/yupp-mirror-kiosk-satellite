#!/bin/bash
# Makes the mirror's system, product and vendor images from copies of
# Radxa's, out/{system,product,vendor}-yupp.img (make-sd-image.py puts them
# in super). Radxa's system has 3 MB free, so curl goes to product.
#
# system:
#   /adb_keys                            this Mac's adb key
#   /system/etc/init/yupp-remote.rc      adb on Wi-Fi, starts the script
#   /system/etc/yupp-remote.sh           joins the mirror's Wi-Fi
#   /system/bin/yupp-buttons             the buttons (build-buttons.sh)
#   /system/etc/init/yupp-buttons.rc
#   /system/bin/ks-install               upstream's Kiosk Satellite installer
#   /system/etc/init/yupp-ks.rc          runs it once Android has booted
#   /system/etc/security/ca-bundle.pem   Android's cacerts in one file, for curl
# product:
#   /bin/curl                            which it needs (build-curl.sh); /product/bin
#                                        comes first in Android's PATH
# vendor:
#   /lib/modules/bcmdhd.ko               Wi-Fi, built for our kernel (build-modules.sh)
#   /build.prop                          portrait: the panel is mounted turned
#                                        by 90 degrees (ORIENTATION_270)
#
# The Wi-Fi name and passphrase come from the Armbian board's
# wpa_supplicant-wlan0.conf; the filled-in script stays on the build SSD.
set -euo pipefail
WORK="${YUPP_WORK:-/Volumes/koa-build/yupp}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${YUPP_WPA_CONF:-$HOME/Projects/armbian-yupp-aiot3399x/packages/bsp/yupp-aiot3399x/wpa_supplicant-wlan0.conf}"
OUT="$WORK/out"
IN="$OUT/images-in"
mkdir -p "$IN"

# The conf keeps only the hashed PSK, and Android's cmd wifi takes the
# passphrase, so it comes from YUPP_WIFI_PASSPHRASE and must hash to the
# conf's PSK.
: "${YUPP_WIFI_PASSPHRASE:?set YUPP_WIFI_PASSPHRASE to the passphrase of the mirror network}"
python3 -I - "$CONF" "$HERE/remote/yupp-remote.sh.in" "$IN/yupp-remote.sh" <<'PY'
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
PY
for f in "$OUT/buttons/yupp-buttons" "$OUT/curl/curl" \
        "$OUT/kernel/drivers/net/wireless/rockchip_wlan/rkwifi/bcmdhd/bcmdhd.ko"; do
    [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
    cp "$f" "$IN/"
done
cp "$HERE/remote/yupp-remote.rc" "$HERE/buttons/yupp-buttons.rc" "$HERE/ks/yupp-ks.rc" "$IN/"
cp "$HERE/../common/init/ks-install.sh" "$IN/ks-install"
cp "$HOME/.android/adbkey.pub" "$IN/adb_keys"
cp "$WORK/radxa-rock4b-a11/parts/system.img" "$OUT/system-yupp.img"
cp "$WORK/radxa-rock4b-a11/parts/vendor.img" "$OUT/vendor-yupp.img"
cp "$WORK/radxa-rock4b-a11/parts/product.img" "$OUT/product-yupp.img"

cat >"$IN/run.sh" <<'RUN'
set -e
apk add -q e2fsprogs e2fsprogs-extra >/dev/null
for l in system_file adb_keys_file vendor_file; do printf 'u:object_r:%s:s0\0' $l >/tmp/$l; done

# put IMAGE DIR NAME SOURCE MODE GID LABEL: replaces or adds DIR/NAME.
put() {
    debugfs -w "$1" <<CMDS >/dev/null 2>&1
cd $2
rm $3
write $4 $3
sif $3 mode 0100$5
sif $3 uid 0
sif $3 gid $6
ea_set -f /tmp/$7 $3 security.selinux
CMDS
}
sys=/w/out/system-yupp.img in=/w/out/images-in
put $sys /system/etc/init yupp-remote.rc $in/yupp-remote.rc 644 0 system_file
put $sys /system/etc yupp-remote.sh $in/yupp-remote.sh 755 2000 system_file
put $sys / adb_keys $in/adb_keys 644 0 adb_keys_file
put $sys /system/bin yupp-buttons $in/yupp-buttons 755 2000 system_file
put $sys /system/etc/init yupp-buttons.rc $in/yupp-buttons.rc 644 0 system_file
put $sys /system/bin ks-install $in/ks-install 755 2000 system_file
put $sys /system/etc/init yupp-ks.rc $in/yupp-ks.rc 644 0 system_file
mkdir -p /tmp/cacerts && debugfs -R "rdump /system/etc/security/cacerts /tmp/cacerts" $sys 2>/dev/null
cat /tmp/cacerts/cacerts/* >/tmp/ca-bundle.pem
put $sys /system/etc/security ca-bundle.pem /tmp/ca-bundle.pem 644 0 system_file

prod=/w/out/product-yupp.img
debugfs -w -f - $prod <<CMDS >/dev/null 2>&1
mkdir /bin
sif /bin mode 040755
sif /bin uid 0
sif /bin gid 2000
ea_set -f /tmp/system_file /bin security.selinux
CMDS
put $prod /bin curl $in/curl 755 2000 system_file

ven=/w/out/vendor-yupp.img
debugfs -R "dump /build.prop /tmp/build.prop" $ven 2>/dev/null
sed -i '/^ro.surface_flinger.primary_display_orientation=/d' /tmp/build.prop
echo ro.surface_flinger.primary_display_orientation=ORIENTATION_270 >>/tmp/build.prop
put $ven / build.prop /tmp/build.prop 644 0 vendor_file
put $ven /lib/modules bcmdhd.ko $in/bcmdhd.ko 644 0 vendor_file

for f in /adb_keys /system/etc/init/yupp-remote.rc /system/etc/yupp-remote.sh /system/bin/yupp-buttons \
        /system/etc/init/yupp-buttons.rc /system/bin/ks-install /system/etc/init/yupp-ks.rc \
        /system/etc/security/ca-bundle.pem "$prod:/bin" "$prod:/bin/curl" \
        "$ven:/build.prop" "$ven:/lib/modules/bcmdhd.ko"; do
    img=$sys; case $f in *:*) img=${f%%:*} f=${f#*:} ;; esac
    printf '%s ' "$f"; debugfs -R "stat $f" "$img" 2>/dev/null | grep -o -E "Mode: +[0-7]+|User: +[0-9]+ +Group: +[0-9]+|Size: [0-9]+" | tr '\n' ' '
    debugfs -R "ea_get $f security.selinux" "$img" 2>/dev/null | tr -d '\n'; echo
done
# A full image takes a write only in part, so compare what went in.
debugfs -R "dump /bin/curl /tmp/curl" $prod 2>/dev/null
debugfs -R "dump /system/etc/security/ca-bundle.pem /tmp/ca-bundle.out" $sys 2>/dev/null
debugfs -R "dump /system/bin/yupp-buttons /tmp/yupp-buttons" $sys 2>/dev/null
debugfs -R "dump /lib/modules/bcmdhd.ko /tmp/bcmdhd.ko" $ven 2>/dev/null
cmp /tmp/curl $in/curl && cmp /tmp/ca-bundle.out /tmp/ca-bundle.pem && cmp /tmp/yupp-buttons $in/yupp-buttons &&
    cmp /tmp/bcmdhd.ko $in/bcmdhd.ko && echo "contents match"
for img in $sys $prod $ven; do e2fsck -fn "$img" 2>&1 | tail -1; done
RUN
container run --rm -c 1 -m 1G --mount type=bind,source="$WORK",target=/w alpine:3.22 sh /w/out/images-in/run.sh 2>&1 | grep -v "^\["
