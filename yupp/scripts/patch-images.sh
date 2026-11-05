#!/bin/bash
# Makes the mirror's system, product and vendor images from copies of
# Radxa's, out/{system,product,vendor}-yupp.img (make-sd-image.py puts them
# in super). Radxa's system has 3 MB free, so curl goes to product.
#
# system:
#   /adb_keys                            this Mac's adb key
#   /system/etc/init/yupp-remote.rc      adb on Wi-Fi, starts the script
#   /system/etc/yupp-remote.sh           joins the mirror's Wi-Fi
#   /system/etc/init/yupp-wifi-watch.rc  Wi-Fi back after a firmware crash
#   /system/etc/yupp-wifi-watch.sh
#   /system/bin/yupp-buttons             the buttons (build-buttons.sh)
#   /system/etc/init/yupp-buttons.rc
#   /system/bin/ks-install               upstream's Kiosk Satellite installer
#   /system/etc/init/yupp-ks.rc          runs it once Android has booted
#   /system/etc/init/yupp-defaults.rc    first-boot settings: Bluetooth on, dark
#   /system/etc/yupp-defaults.sh
#   /system/etc/security/ca-bundle.pem   Android's cacerts in one file, for curl
# product:
#   /app/webview/webview.apk             LineageOS's Chromium WebView, as upstream's
#                                        Shows ship it (fetch-webview.sh)
#   /media/bootanimation.zip             upstream's Kiosk Satellite animation, for the
#                                        mirror's screen (make-bootanimation.py)
#   /bin/curl                            which it needs (build-curl.sh); /product/bin
#                                        comes first in Android's PATH
# vendor:
#   /lib/modules/bcmdhd.ko               Wi-Fi, built for our kernel (build-modules.sh)
#   /etc/firmware/config.txt             bcmdhd's settings: PM=0 keeps the chip's power
#                                        save off (it put it back after every scan)
#   /etc/firmware/fw_bcm43438a1.bin      Radxa's, with its deliberate crash for chips
#   /etc/firmware/fw_bcm43438a1_apsta.bin without a licence key turned off
#   /build.prop                          portrait: the panel is mounted turned
#                                        by 90 degrees (ORIENTATION_270); the echo
#                                        canceller's gain on the AC108 (0 dB)
#   /lib/libyuppaec.so                   the echo canceller, preloaded into the
#   /etc/init/yupp-aec.rc                audio HAL (build-aec.sh, aec/)
#
# images/remove.txt lists the apps left out, as upstream leaves them out.
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
for f in "$OUT/buttons/yupp-buttons" "$OUT/curl/curl" "$OUT/webview/webview.apk" \
        "$OUT/kernel/drivers/net/wireless/rockchip_wlan/rkwifi/bcmdhd/bcmdhd.ko" "$OUT/aec/libyuppaec.so" "$OUT/bootanimation/bootanimation.zip"; do
    [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
    cp "$f" "$IN/"
done
cp "$HERE/remote/yupp-remote.rc" "$HERE/buttons/yupp-buttons.rc" "$HERE/ks/yupp-ks.rc" "$HERE/defaults/yupp-defaults.rc" "$HERE/defaults/yupp-defaults.sh" \
    "$HERE/wifi/yupp-wifi-watch.rc" "$HERE/wifi/yupp-wifi-watch.sh" "$HERE/wifi/config.txt" "$HERE/aec/yupp-aec.rc" "$IN/"
cp "$HERE/../common/init/ks-install.sh" "$IN/ks-install"
cp "$HOME/.android/adbkey.pub" "$IN/adb_keys"
grep -v -e '^#' -e '^$' "$HERE/images/remove.txt" >"$IN/remove.txt"
cp "$WORK/radxa-rock4b-a11/parts/system.img" "$OUT/system-yupp.img"
cp "$WORK/radxa-rock4b-a11/parts/vendor.img" "$OUT/vendor-yupp.img"
cp "$WORK/radxa-rock4b-a11/parts/product.img" "$OUT/product-yupp.img"
cp "$WORK/radxa-rock4b-a11/parts/system_ext.img" "$OUT/system_ext-yupp.img"

cat >"$IN/run.sh" <<'RUN'
set -e
apk add -q e2fsprogs e2fsprogs-extra >/dev/null
for l in system_file adb_keys_file vendor_file vendor_configs_file; do printf 'u:object_r:%s:s0\0' $l >/tmp/$l; done

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
prod=/w/out/product-yupp.img ext=/w/out/system_ext-yupp.img

# rmtree IMAGE PATH: debugfs has no recursive rm.
rmtree() {
    debugfs -R "ls -p $2" "$1" 2>/dev/null | awk -F/ 'NF > 6 && $6 != "." && $6 != ".." { print substr($3, 1, 2), $6 }' |
    while read type name; do
        if [ "$type" = 04 ]; then rmtree "$1" "$2/$name"; else echo "rm $2/$name"; fi
    done
    echo "rmdir $2"
}
# remove.txt paths start with the partition: system/ is /system in the
# system image (its root is /), system_ext/ and product/ are their images' roots.
while read p; do
    case $p in
    system/*) img=$sys path=/$p ;;
    system_ext/*) img=$ext path=/${p#system_ext/} ;;
    product/*) img=$prod path=/${p#product/} ;;
    esac
    debugfs -R "stat $path" "$img" 2>/dev/null | grep -q Type: || { echo "not in the image: $p"; exit 1; }
    rmtree "$img" "$path" >/tmp/rm.cmds
    debugfs -w -f /tmp/rm.cmds "$img" >/dev/null 2>&1
    debugfs -R "stat $path" "$img" 2>/dev/null | grep -q Type: && { echo "still there: $p"; exit 1; }
done <$in/remove.txt
echo "removed $(wc -l <$in/remove.txt) apps"
put $sys /system/etc/init yupp-remote.rc $in/yupp-remote.rc 644 0 system_file
put $sys /system/etc yupp-remote.sh $in/yupp-remote.sh 755 2000 system_file
put $sys /system/etc/init yupp-wifi-watch.rc $in/yupp-wifi-watch.rc 644 0 system_file
put $sys /system/etc yupp-wifi-watch.sh $in/yupp-wifi-watch.sh 755 2000 system_file
put $sys / adb_keys $in/adb_keys 644 0 adb_keys_file
put $sys /system/bin yupp-buttons $in/yupp-buttons 755 2000 system_file
put $sys /system/etc/init yupp-buttons.rc $in/yupp-buttons.rc 644 0 system_file
put $sys /system/bin ks-install $in/ks-install 755 2000 system_file
put $sys /system/etc/init yupp-ks.rc $in/yupp-ks.rc 644 0 system_file
put $sys /system/etc/init yupp-defaults.rc $in/yupp-defaults.rc 644 0 system_file
put $sys /system/etc yupp-defaults.sh $in/yupp-defaults.sh 755 2000 system_file
mkdir -p /tmp/cacerts && debugfs -R "rdump /system/etc/security/cacerts /tmp/cacerts" $sys 2>/dev/null
cat /tmp/cacerts/cacerts/* >/tmp/ca-bundle.pem
put $sys /system/etc/security ca-bundle.pem /tmp/ca-bundle.pem 644 0 system_file

# mkdir IMAGE DIR GID
mkdir_() {
    debugfs -w -f - "$1" <<CMDS >/dev/null 2>&1
mkdir $2
sif $2 mode 040755
sif $2 uid 0
sif $2 gid $3
ea_set -f /tmp/system_file $2 security.selinux
CMDS
}
mkdir_ $prod /bin 2000
put $prod /bin curl $in/curl 755 2000 system_file
mkdir_ $prod /app/webview 0
put $prod /app/webview webview.apk $in/webview.apk 644 0 system_file
mkdir_ $prod /media 0
put $prod /media bootanimation.zip $in/bootanimation.zip 644 0 system_file

ven=/w/out/vendor-yupp.img
debugfs -R "dump /build.prop /tmp/build.prop" $ven 2>/dev/null
sed -i '/^ro.surface_flinger.primary_display_orientation=/d' /tmp/build.prop
echo ro.surface_flinger.primary_display_orientation=ORIENTATION_270 >>/tmp/build.prop
sed -i '/^ro.vendor.amznaec.gain_db=/d' /tmp/build.prop
echo ro.vendor.amznaec.gain_db=0 >>/tmp/build.prop
# As upstream's Echo images since 2026.10.6: Kiosk Satellite (2026.11.1+)
# cancels the echo itself (GTCRN) and needs the microphones raw, at a fixed
# echo delay. libyuppaec.so stays loaded but passes them through;
# persist.vendor.amznaec.enable 1 and a restart of the HAL bring it back.
sed -i '/^ro.vendor.amznaec.enable=/d' /tmp/build.prop
echo ro.vendor.amznaec.enable=0 >>/tmp/build.prop
put $ven / build.prop /tmp/build.prop 644 0 vendor_file
put $ven /lib/modules bcmdhd.ko $in/bcmdhd.ko 644 0 vendor_file
put $ven /etc/firmware config.txt $in/config.txt 644 0 vendor_file
# Radxa's AP6212 firmware (7.45.96.76, Synaptics build) reads a licence key from
# the chip's OTP at boot. Without it (our module), its watchdog crashes the
# firmware on purpose: once up for 10 minutes, every second a random number
# ending in 888 (1 in 1000) means "internal error" and a write to address 0
# (TRAP c @ pc 0x14494). The function that reports "no licence" (0x53a8) now
# answers 0: movs r0, #0; bx lr. The _apsta file is the same binary.
for fw in fw_bcm43438a1.bin fw_bcm43438a1_apsta.bin; do
    debugfs -R "dump /etc/firmware/$fw /tmp/$fw" $ven 2>/dev/null
    echo "0c34a106190ca071732ee5e2f8ebbb6e4c6b912a  /tmp/$fw" | sha1sum -c -s || { echo "unexpected $fw"; exit 1; }
    printf '\000\040\160\107' | dd of=/tmp/$fw bs=1 seek=$((0x53a8)) conv=notrunc 2>/dev/null
    echo "d2ec1c774ce1d67162c7446b8e18f5561b9eea4f  /tmp/$fw" | sha1sum -c -s || { echo "patching $fw failed"; exit 1; }
    put $ven /etc/firmware $fw /tmp/$fw 644 0 vendor_configs_file
done
put $ven /lib libyuppaec.so $in/libyuppaec.so 644 0 vendor_file
put $ven /etc/init yupp-aec.rc $in/yupp-aec.rc 644 0 vendor_configs_file

for f in /adb_keys /system/etc/init/yupp-remote.rc /system/etc/yupp-remote.sh \
        /system/etc/init/yupp-wifi-watch.rc /system/etc/yupp-wifi-watch.sh /system/bin/yupp-buttons \
        /system/etc/init/yupp-buttons.rc /system/bin/ks-install /system/etc/init/yupp-ks.rc /system/etc/init/yupp-defaults.rc /system/etc/yupp-defaults.sh \
        /system/etc/security/ca-bundle.pem "$prod:/bin" "$prod:/bin/curl" \
        "$prod:/app/webview" "$prod:/app/webview/webview.apk" "$prod:/media/bootanimation.zip" \
        "$ven:/build.prop" "$ven:/lib/modules/bcmdhd.ko" "$ven:/etc/firmware/config.txt" \
        "$ven:/etc/firmware/fw_bcm43438a1.bin" "$ven:/etc/firmware/fw_bcm43438a1_apsta.bin" "$ven:/lib/libyuppaec.so" "$ven:/etc/init/yupp-aec.rc"; do
    img=$sys; case $f in *:*) img=${f%%:*} f=${f#*:} ;; esac
    printf '%s ' "$f"; debugfs -R "stat $f" "$img" 2>/dev/null | grep -o -E "Mode: +[0-7]+|User: +[0-9]+ +Group: +[0-9]+|Size: [0-9]+" | tr '\n' ' '
    debugfs -R "ea_get $f security.selinux" "$img" 2>/dev/null | tr -d '\n'; echo
done
# A full image takes a write only in part, so compare what went in.
debugfs -R "dump /bin/curl /tmp/curl" $prod 2>/dev/null
debugfs -R "dump /app/webview/webview.apk /tmp/webview.apk" $prod 2>/dev/null
debugfs -R "dump /system/etc/security/ca-bundle.pem /tmp/ca-bundle.out" $sys 2>/dev/null
debugfs -R "dump /system/bin/yupp-buttons /tmp/yupp-buttons" $sys 2>/dev/null
debugfs -R "dump /lib/modules/bcmdhd.ko /tmp/bcmdhd.ko" $ven 2>/dev/null
debugfs -R "dump /lib/libyuppaec.so /tmp/libyuppaec.so" $ven 2>/dev/null
cmp /tmp/curl $in/curl && cmp /tmp/webview.apk $in/webview.apk && cmp /tmp/ca-bundle.out /tmp/ca-bundle.pem && cmp /tmp/yupp-buttons $in/yupp-buttons &&
    cmp /tmp/bcmdhd.ko $in/bcmdhd.ko && cmp /tmp/libyuppaec.so $in/libyuppaec.so && echo "contents match"
for img in $sys $ext $prod $ven; do e2fsck -fn "$img" 2>&1 | tail -1; done
RUN
container run --rm -c 1 -m 1G --mount type=bind,source="$WORK",target=/w alpine:3.22 sh /w/out/images-in/run.sh 2>&1 | grep -v "^\["
