#!/system/bin/sh
# The mirror's first-boot settings. Each is set once (persist.yupp.<name>_default
# records it), so changing it afterwards sticks.
once() {
    n=$1
    shift
    [ "$(getprop persist.yupp.${n}_default)" = 1 ] && return
    "$@" && setprop persist.yupp.${n}_default 1
}
# Bluetooth on: Radxa's image leaves it off, and Kiosk Satellite's Bluetooth
# proxy needs it.
once bt svc bluetooth enable
# Dark: a mirror shows black as glass; Radxa's image starts light.
once dark cmd uimode night yes
