#!/bin/bash
# The container half of build-modules.sh: the loadable modules of the kernel
# build-kernel.sh made (same .config, same tree), for the vendor's
# /vendor/lib/modules. The vendor's own were built for Radxa's kernel, and
# with MODVERSIONS ours refuses them ("disagrees about version of symbol
# module_layout"): bcmdhd.ko (AP6XXX, the mirror's BCM4354 Wi-Fi) above all.
set -euo pipefail
JOBS="$1"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  build-essential bc bison flex libssl-dev python3 python-is-python3 kmod >/dev/null

O=/w/out/kernel
cd /w/kernel-4.19
make O="$O" ARCH=arm64 -j"$JOBS" modules 2>&1 | tail -5
find "$O" -name '*.ko' -newer "$O/.config" -exec ls -l {} \;
for m in $(find "$O" -name bcmdhd.ko); do
  modinfo "$m" | grep -E '^(vermagic|filename)'
  aarch64-linux-gnu-strip --strip-debug "$m" 2>/dev/null || strip --strip-debug "$m"
  ls -l "$m"
done
