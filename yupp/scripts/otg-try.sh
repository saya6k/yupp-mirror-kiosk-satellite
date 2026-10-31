#!/bin/bash
# Tries a boot image on the mirror once, over USB adb, with no SD swap.
#
#   otg-try.sh IMAGE [REPORT]
#
# The mirror runs a boot that works (its boot partition). IMAGE goes in the
# recovery partition, and the mirror restarts into it once: Rockchip's U-Boot
# takes the boot mode from a PMU register (mode-recovery 0x5242c303 at
# 0xff320300, the tree's reboot-mode node), which a warm reset keeps and a
# power cut clears. Nothing goes in misc, so a power cycle always comes back
# to the working boot.
#
# A diagnostic IMAGE (diag/init) writes its report to backup and restarts;
# the report is then read back to REPORT. If the mirror does not come back,
# IMAGE stopped before userspace: cut the mirror's power and plug it back in.
#   otg-try.sh --read REPORT   only reads the report back (after a power cycle)
set -euo pipefail

read_report() {
  adb root >/dev/null; sleep 3; adb wait-for-device
  adb shell 'dd if=/dev/block/by-name/backup bs=1M count=4 2>/dev/null' |
    python3 -I -c 'import sys; d = sys.stdin.buffer.read(); i = d.find(b"YUPPDIAG")
sys.stdout.write(d[i:d.find(b"YUPPEND", i)].decode("utf-8", "replace") if i >= 0 else "no report: the image never reached userspace\n")' >"$1"
  head -3 "$1"; echo "report: $1"
}

if [ "$1" = --read ]; then read_report "$2"; exit; fi
img="$1"
report="${2:-${img%.img}.report.txt}"

adb root >/dev/null; sleep 3; adb wait-for-device
adb push "$img" /data/local/tmp/try.img >/dev/null
adb shell 'dd if=/data/local/tmp/try.img of=/dev/block/by-name/recovery bs=1M conv=fsync 2>/dev/null &&
  dd if=/dev/zero of=/dev/block/by-name/backup bs=1M count=4 conv=fsync 2>/dev/null &&
  rm /data/local/tmp/try.img && sync'
echo "$(date +%T) restarting into $(basename "$img")"
# reboot-to (diag/reboot-to.c) restarts with "recovery" straight through the
# kernel: its reboot-mode driver sets the register, and init never writes a
# bootloader message to misc. sysrq b would not do: the restart handler sets
# the mode back to normal.
adb shell "[ -x /data/local/tmp/reboot-to ]" || { adb push "$(dirname "$0")/../diag/reboot-to" /data/local/tmp/ >/dev/null; adb shell chmod 755 /data/local/tmp/reboot-to; }
adb shell '/data/local/tmp/reboot-to recovery' >/dev/null 2>&1 || true

sleep 20
for i in $(seq 1 60); do
  adb devices | grep -q 'device$' && break
  sleep 5
done
if ! adb devices | grep -q 'device$'; then
  echo "$(date +%T) the mirror did not come back: cut its power and plug it back in, then read the report with: $0 --read $report" >&2
  exit 1
fi
echo "$(date +%T) back"
read_report "$report"
