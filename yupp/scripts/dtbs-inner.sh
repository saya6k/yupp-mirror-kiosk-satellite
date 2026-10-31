#!/bin/bash
# Builds device trees from the kernel tree in the build container and
# decompiles each to a .dts next to it, for comparing. Arguments are DTB
# targets such as rockchip/rk3399-sapphire-excavator-edp.dtb.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  build-essential bc bison flex libssl-dev python3 python-is-python3 device-tree-compiler >/dev/null

O=/w/out/kernel
cd /w/kernel-4.19
for t in "$@"; do
  make O="$O" ARCH=arm64 "$t" 2>&1 | tail -3
  dtc -I dtb -O dts -o "$O/arch/arm64/boot/dts/${t%.dtb}.decompiled.dts" "$O/arch/arm64/boot/dts/$t" 2>/dev/null
  ls -l "$O/arch/arm64/boot/dts/$t"
done
