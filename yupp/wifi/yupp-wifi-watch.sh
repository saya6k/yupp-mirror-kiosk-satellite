#!/system/bin/sh
# Keeps the mirror on Wi-Fi, its only way onto the network.
#
# The AP6212's firmware traps now and then (dmesg: "FIRMWARE HALTED : set
# BUS DOWN", after 52 minutes once, during a long adb push). bcmdhd sends
# HANG and wlan0 goes down, and Android 11's self recovery answers an
# interface that went down by turning Wi-Fi off ("STA interface down, disable
# wifi"). This turns it on again; bcmdhd then powers the chip up and loads the
# firmware anew. When Wi-Fi stays on but the gateway stops answering for two
# minutes, it turns Wi-Fi off and on.
#
# Each time, what the kernel and Android said goes to /data/yupp-log/wifi-*.txt
# (the last 10 are kept). setprop persist.yupp.wifi_watch 0 turns this off.
L=/data/yupp-log
record() {
    log -t yupp-wifi-watch "$1"
    mkdir -p $L
    f=$L/wifi-$(date +%m%d-%H%M%S).txt
    { date; echo "$1"; echo; dmesg | tail -80; echo; logcat -d -b main,system -t 400 | grep -iE 'wifi|wlan|supplicant'; } >$f 2>&1
    ls -t $L/wifi-*.txt | tail -n +11 | xargs rm -f
}
bad=0
while :; do
    sleep 30
    [ "$(getprop persist.yupp.wifi_watch)" = 0 ] && continue
    [ "$(getprop sys.boot_completed)" = 1 ] || continue
    if [ "$(settings get global wifi_on)" = 0 ]; then
        record "Wi-Fi is off, turning it on"
        cmd wifi set-wifi-enabled enabled
        bad=0
        continue
    fi
    gw=$(ip route show table all | sed -n 's/^default via \([0-9.]*\) dev wlan0.*/\1/p' | head -n 1)
    if [ -n "$gw" ] && ping -c 1 -W 3 "$gw" >/dev/null 2>&1; then
        bad=0
        continue
    fi
    bad=$((bad + 1))
    if [ $bad -ge 4 ]; then
        record "no answer from the gateway (${gw:-none}) for 2 minutes, restarting Wi-Fi"
        cmd wifi set-wifi-enabled disabled
        sleep 5
        cmd wifi set-wifi-enabled enabled
        bad=0
    fi
done
