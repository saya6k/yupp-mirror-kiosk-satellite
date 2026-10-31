#!/bin/bash
# Tries a kernel, tree and ramdisk on the mirror from its running Android,
# with kexec: no bootloader, no partition but backup is touched, and a hang
# is undone by a power cycle (the mirror then boots its boot partition).
#
#   kexec-try.sh DIR DTB RAMDISK [REPORT]
#
# DIR holds Image and kx/ (kexec-tools with its musl loader and libraries).
# DTB must carry what U-Boot adds (fixups.sh: /memory, serial-number,
# bootargs_ext). The command line is the running one. A diagnostic RAMDISK
# (diag/init) writes its report to backup and reboots; the report is then
# read back to REPORT. YUPP_ADB is the mirror's Wi-Fi adb address (host:5555).
set -euo pipefail
dir="$1" dtb="$2" ramdisk="$3"
report="${4:-${dtb%.dtb}.report.txt}"
T=/data/local/tmp

adb root >/dev/null 2>&1; sleep 3; adb connect "${YUPP_ADB:?set YUPP_ADB to the mirror's host:5555}" >/dev/null 2>&1; adb wait-for-device
adb shell "mkdir -p $T/kx"
adb shell "[ -f $T/kx/kexec ]" || adb push "$dir"/kx/{kexec,ld-musl-aarch64.so.1,libz.so.1,liblzma.so.5} $T/kx/ >/dev/null
adb shell "[ -f $T/Image ] && [ \$(stat -c %s $T/Image) = $(stat -f %z "$dir/Image") ]" || adb push "$dir/Image" $T/Image >/dev/null
adb push "$dtb" $T/try.dtb >/dev/null
adb push "$ramdisk" $T/try.rd >/dev/null
adb shell "dd if=/dev/zero of=/dev/block/by-name/backup bs=1M count=4 conv=fsync 2>/dev/null; sync"
adb shell "K='$T/kx/ld-musl-aarch64.so.1 --library-path $T/kx $T/kx/kexec';
  \$K -l $T/Image --dtb=$T/try.dtb --initrd=$T/try.rd --command-line=\"\$(cat /proc/cmdline)\" && echo loaded"
echo "$(date +%T) kexec into $(basename "$dtb") + $(basename "$ramdisk")"
adb shell "sync; $T/kx/ld-musl-aarch64.so.1 --library-path $T/kx $T/kx/kexec -e" >/dev/null 2>&1 &
sleep 30
for i in $(seq 1 60); do
  adb devices | grep -q 'device$' && break
  sleep 5
done
if ! adb devices | grep -q 'device$'; then
  echo "$(date +%T) the mirror did not come back: cut its power, plug it back in, then: $(dirname "$0")/otg-try.sh --read $report" >&2
  exit 1
fi
echo "$(date +%T) back"
"$(dirname "$0")/otg-try.sh" --read "$report"
