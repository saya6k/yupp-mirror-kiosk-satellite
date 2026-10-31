#!/bin/bash
# Builds the kernel's loadable modules (modules-inner.sh) in the same
# throwaway arm64 container as build-kernel.sh, on the build SSD.
set -euo pipefail
WORK="${YUPP_WORK:-/Volumes/koa-build/yupp}"
HERE="$(cd "$(dirname "$0")" && pwd)"
JOBS="${JOBS:-6}"
[[ -f "$WORK/out/kernel/.config" ]] || { echo "build the kernel first (build-kernel.sh)" >&2; exit 1; }
cp "$HERE/modules-inner.sh" "$WORK/out/modules-inner.sh"
container run --rm -c "$JOBS" -m 6G \
  --mount type=bind,source="$WORK",target=/w \
  ubuntu:20.04 bash /w/out/modules-inner.sh "$JOBS"
