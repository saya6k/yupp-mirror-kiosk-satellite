#!/bin/bash
# The container half of build-kernel.sh.
set -euo pipefail
JOBS="$1"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  build-essential bc bison flex libssl-dev python3 python-is-python3 kmod cpio lz4 >/dev/null

O=/w/out/kernel
cd /w/kernel-4.19
cp /w/radxa-rock4b-a11/kernel-4.19.232.config "$O/.config"
# The mirror's codec, an ES8388 on i2c.
scripts/config --file "$O/.config" --enable SND_SOC_ES8328_I2C --enable SND_SOC_ES8328
# Bring-up with no serial console: kexec tries a kernel and tree from the
# running Android without the bootloader (a hang is undone by a power cycle),
# /dev/mem reads and sets registers such as the boot mode.
scripts/config --file "$O/.config" --enable KEXEC --enable DEVMEM
make O="$O" ARCH=arm64 olddefconfig >/dev/null
grep -E "CONFIG_SND_SOC_ES8328(_I2C)?=|CONFIG_KEXEC=|CONFIG_DEVMEM=" "$O/.config"
make O="$O" ARCH=arm64 -j"$JOBS" Image 2>&1 | tail -20
ls -l "$O/arch/arm64/boot/Image"
strings "$O/arch/arm64/boot/Image" | grep -m1 "Linux version"
