#!/system/bin/sh
# Turns Wi-Fi back on after Android turned it off on a firmware crash.
#
# The AP6212's firmware traps now and then (dmesg: "FIRMWARE HALTED : set
# BUS DOWN", after 52 minutes once, during a long adb push). bcmdhd sends
# HANG and wlan0 goes down, and Android 11's self recovery answers an
# interface that went down by turning Wi-Fi off ("STA interface down, disable
# wifi"). The mirror has no other way onto the network, so this turns it on
# again; bcmdhd then powers the chip up and loads the firmware anew.
# setprop persist.yupp.wifi_watch 0 turns it off.
while :; do
    sleep 30
    [ "$(getprop persist.yupp.wifi_watch)" = 0 ] && continue
    [ "$(getprop sys.boot_completed)" = 1 ] || continue
    if [ "$(settings get global wifi_on)" = 0 ]; then
        log -t yupp-wifi-watch "Wi-Fi is off, turning it on"
        cmd wifi set-wifi-enabled enabled
    fi
done
