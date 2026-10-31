#!/bin/bash
# Bring-up loop for the mirror's SD in this Mac's card reader, without the
# serial console, USB or network the mirror does not have yet.
#
#   sudo sd-test.sh write BOOT.img   puts BOOT.img in the boot partition and
#                                    empties metadata
#   sudo sd-test.sh check            after a boot on the mirror: what wrote
#                                    to the SD
#   sudo sd-test.sh system SYSTEM.img  puts SYSTEM.img in super's system
#                                    partition; metadata stays, since it holds
#                                    the keys of the /data already there
#   sudo sd-test.sh pull             copies metadata (yupp-remote's snapshot
#                                    in /yupp), misc and cache to $YUPP_WORK/out
#   sudo sd-test.sh prep             does what Radxa's first boot leaves to its
#                                    recovery (misc says "recovery --wipe_all"),
#                                    which carries the Rock Pi's tree and never
#                                    gets there on the mirror: GPT with userdata
#                                    to the end of the SD, misc empty, cache
#                                    ext4, metadata and the start of userdata
#                                    empty so Android formats them
#
# Android 11's first-stage init formats the empty metadata partition, so an
# ext4 metadata means the kernel ran and reached init. Partition offsets are
# those of Radxa's Rock4b-android11-20220819 GPT.
set -euo pipefail
SIZE=31914983424             # the mirror's SD; anything else is refused
BOOT_MIB=25                  # sector 51200
META_MIB=935                 # sector 1914880, 16 MiB
SYSTEM_MIB=953               # byte 999292928 inside super
SYSTEM_SIZE=983883776
# The build SSD, or the copy on the NAS while the SSD is unplugged (sudo
# drops YUPP_WORK, so the fallback is picked here).
WORK="${YUPP_WORK:-/Volumes/koa-build/yupp}"
[ -d "$WORK/out" ] || WORK=/Volumes/Temp/Recording/yupp

disk=$(for d in $(diskutil list external physical | awk '/^\/dev\//{print $1}'); do
  if [ "$(diskutil info "$d" | awk -F'[()]' '/Disk Size/{print $2}' | awk '{print $1}')" = "$SIZE" ]; then
    echo "$d"
  fi
done)
[ "$(echo "$disk" | wc -w)" -eq 1 ] || { echo "the mirror's SD ($SIZE bytes) is not plugged in, or more than one disk matches" >&2; exit 1; }
raw=/dev/r${disk#/dev/}
diskutil unmountDisk "$disk" >/dev/null

case "${1:-}" in
write)
  img="$2"
  [ "$(stat -f %z "$img")" -le $((40 * 1024 * 1024)) ] || { echo "$img is larger than the boot partition" >&2; exit 1; }
  dd if="$img" of="$raw" bs=1m seek=$BOOT_MIB conv=sync 2>/dev/null
  # metadata holds the key of the encrypted userdata: emptying one without
  # the other leaves a /data that never mounts, so both go.
  dd if=/dev/zero of="$raw" bs=1m seek=$META_MIB count=16 2>/dev/null
  dd if=/dev/zero of="$raw" bs=1m seek=4164 count=16 2>/dev/null
  dd if=/dev/zero of="$raw" bs=1m seek=167 count=4 2>/dev/null    # backup: no stale diag report
  sync
  echo "boot <- $img, metadata, userdata and the diag report emptied ($disk)"
  diskutil eject "$disk" >/dev/null
  ;;
check)
  # Whole sectors into variables: a reader that stops early would SIGPIPE
  # dd and, with pipefail, end the script without a word.
  meta=$(dd if="$raw" bs=512 skip=$((META_MIB * 2048 + 2)) count=1 2>/dev/null | xxd -p | tr -d '\n')
  meta=${meta:112:4}         # the ext4 magic, byte 0x438 of the partition
  vendor=$(dd if="$raw" bs=512 skip=7168 count=1 2>/dev/null | xxd -p | tr -d '\n')
  vendor=$(echo "${vendor:0:8}" | xxd -r -p)
  echo "U-Boot vendor storage: $([ "$vendor" = DVKR ] && echo written || echo empty)"
  if [ "$meta" = 53ef ]; then
    echo "metadata: ext4, the kernel ran and reached Android's first-stage init"
  else
    echo "metadata: still empty, Android's init never ran"
  fi
  diskutil eject "$disk" >/dev/null
  ;;
system)
  img="$2"
  [ "$(stat -f %z "$img")" = $SYSTEM_SIZE ] || { echo "$img is not $SYSTEM_SIZE bytes" >&2; exit 1; }
  dd if="$img" of="$raw" bs=1m seek=$SYSTEM_MIB 2>/dev/null
  sync
  echo "system <- $img ($disk)"
  diskutil eject "$disk" >/dev/null
  ;;
pull)
  # metadata (yupp-remote's snapshot), misc (the bootloader message: a
  # failed /data mount sends init to recovery) and cache (recovery's logs).
  dd if="$raw" of="$WORK/out/metadata.img" bs=1m skip=$META_MIB count=16 2>/dev/null
  dd if="$raw" of="$WORK/out/misc.img" bs=1m skip=16 count=4 2>/dev/null
  dd if="$raw" of="$WORK/out/cache.img" bs=1m skip=551 count=384 2>/dev/null
  chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$WORK/out/metadata.img" "$WORK/out/misc.img" "$WORK/out/cache.img"
  echo "metadata, misc, cache -> $WORK/out/"
  diskutil eject "$disk" >/dev/null
  ;;
prep)
  for f in gpt-primary.bin gpt-backup.bin cache-ext4.img; do
    [ -f "$WORK/out/$f" ] || { echo "missing $WORK/out/$f" >&2; exit 1; }
  done
  dd if="$WORK/out/gpt-primary.bin" of="$raw" bs=512 2>/dev/null
  dd if="$WORK/out/gpt-backup.bin" of="$raw" bs=512 seek=$((SIZE / 512 - 33)) 2>/dev/null
  dd if=/dev/zero of="$raw" bs=1m seek=16 count=4 2>/dev/null                 # misc
  dd if="$WORK/out/cache-ext4.img" of="$raw" bs=1m seek=551 2>/dev/null       # cache
  dd if=/dev/zero of="$raw" bs=1m seek=$META_MIB count=16 2>/dev/null         # metadata
  dd if=/dev/zero of="$raw" bs=1m seek=4164 count=16 2>/dev/null              # userdata start
  sync
  echo "GPT grown, misc empty, cache ext4, metadata and userdata emptied ($disk)"
  diskutil eject "$disk" >/dev/null
  ;;
diag)
  # diag/init's report (start of backup, sector 342016) to $2, and misc
  # emptied: adb reboot recovery leaves "boot-recovery" there, and with no
  # recovery to clear it every boot would run the diagnostic again.
  out="$2"
  dd if="$raw" of="$out" bs=1m skip=167 count=4 2>/dev/null
  chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$out"
  dd if=/dev/zero of="$raw" bs=1m seek=16 count=4 2>/dev/null
  sync
  echo "backup start -> $out, misc emptied ($disk)"
  diskutil eject "$disk" >/dev/null
  ;;
*) echo "usage: sudo $0 write BOOT.img | check | system SYSTEM.img | pull | prep | diag OUT" >&2; exit 2 ;;
esac
