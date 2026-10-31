#!/bin/bash
# Builds the mirror's kernel: Radxa's Rock Pi 4B Android 11 configuration
# (taken from its boot image's IKCONFIG) plus what the mirror needs, from
# rockchip-linux/kernel develop-4.19 (4.19.232, the same version).
#
# Runs on the Mac. The tree and the output live on the build SSD; the build
# runs in a throwaway arm64 Ubuntu 20.04 container, so nothing but the
# container's packages touches the internal disk, and only while it runs.
set -euo pipefail

WORK="${YUPP_WORK:-/Volumes/koa-build/yupp}"
HERE="$(cd "$(dirname "$0")" && pwd)"
JOBS="${JOBS:-6}"

[[ -f "$WORK/kernel-4.19/Makefile" ]] || { echo "no kernel tree in $WORK/kernel-4.19" >&2; exit 1; }
[[ -f "$WORK/radxa-rock4b-a11/kernel-4.19.232.config" ]] || { echo "no Radxa config" >&2; exit 1; }
mkdir -p "$WORK/out/kernel"
cp "$HERE/kernel-inner.sh" "$WORK/out/kernel-inner.sh"

container run --rm -c "$JOBS" -m 6G \
  --mount type=bind,source="$WORK",target=/w \
  ubuntu:20.04 bash /w/out/kernel-inner.sh "$JOBS"
