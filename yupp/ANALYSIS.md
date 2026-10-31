# Fitting the YUPP mirror into lineageos-echo-kiosk-satellite

Goal: add the mirror as one more device of [jxlarrea/lineageos-echo-kiosk-satellite]
(upstream `fd470a4`), changing as little of upstream as possible.

## How upstream is built

- One **LineageOS 18.1** (Android 11) tree for every device; `manifest/local.xml` adds the
  device projects, `scripts/stage-tree.sh` copies the layer in and applies patches.
- `common/` → staged as `vendor/kiosk-satellite`. Inherited from a device tree through
  `config/common.mk` (every Echo), `config/show.mk` (screens) and `config/BoardConfig.mk`.
- `device/<dev>/device.mk` → `device/kiosk-satellite/<dev>`: a few properties per device
  (hostname, media volume default, mic gain).
- `sources/device/amazon/<dev>/`: a device tree of the repo's own where none exists upstream.
- `scripts/extract-<dev>-blobs.sh`: proprietary files taken from the stock firmware at staging.
- `patches/<set>/<project path>/NNNN-*.patch`, sets `common` then `<dev>`.

## What in `common/` is tied to the Echos

| Part | Echo-specific? | For the mirror |
|---|---|---|
| EchoService (`echo_service`, Wi-Fi, time, adb, screen, volume, BT audio, locale, hostname) | No | Reuse as is |
| Privacy state (`gpio-privacy`, `amazon-gating`) | Yes, but falls back to "no privacy button" | Reuse as is |
| Thermal (`thermal_zone*` scan) | Mostly generic | Reuse as is |
| `ks-install.sh`, `init.kiosk-satellite.rc` (KS install, device owner, grants, adb Wi-Fi, trimmed services) | Double-tap writes to `gt9xx`/`focaltech` sysfs, harmless when absent | Reuse as is |
| Overlays, RROs (no setup wizard, lock screen, Wi-Fi WPA3 transition, DHCP hostname) | No (LineageOS 18.1) | Reuse as is |
| `overrides` (debloat), memory props, boot animation, wallpaper | No | Reuse; add a 1080/1920 boot animation size |
| `libamznaec_shim` (`show.mk`) | **Yes**: wraps the MT8163 audio HAL, FPGA speaker reference | Leave out for the mirror |
| `biscuit-pryond` + Pryon blobs (`common.mk`) | **Yes**: 32-bit blobs from the Echo Dot's Fire OS OTA, private DAVS models | Leave out at first |
| OTA (`SystemUpdate.java`, `twrp-update.sh`) | Needs TWRP `3.7.0_9-0` exactly | Needs a TWRP for the mirror; phase 2 |
| `BoardConfig.mk` (kernel LOCALVERSION) | Generic | Reuse |

So the layer itself needs **two guards**, not a rewrite: one around `libamznaec_shim` in
`show.mk`, one around Pryon in `common.mk` (e.g. `ifneq ($(KS_NO_AMZNAEC),true)`).

## The mirror as a new device `yupp`

| Upstream file | Change |
|---|---|
| `Makefile`, `scripts/stage-tree.sh`, `scripts/build.sh`, `scripts/check-image.sh` | Add `yupp` to the device lists and names |
| `manifest/local.xml` | Add the RK3399 projects (kernel, Rockchip HALs if built from source) |
| `common/config/show.mk`, `common/config/common.mk` | The two guards above |
| **new** `sources/device/smdt/yupp/` | Device tree: BoardConfig, fstab, init, audio/media configs, inherits `show.mk` |
| **new** `device/yupp/device.mk` | `ro.echo.hostname=yupp-mirror-ks`, volume default |
| **new** `scripts/extract-yupp-blobs.sh` | Vendor/ODM from Radxa's Rock Pi 4B Android 11 image, like `extract-biscuit-blobs.sh` |
| **new** `patches/yupp/` | Kernel (YUPP DTS, GM8775C), anything the Rockchip vendor needs |
| **new** `CHANGELOG-yupp.md`, `docs/yupp-mirror.md` | Releases and guide |

Everything else upstream stays untouched, so later upstream changes merge cleanly.

## RK3399 pieces

- **Vendor (HALs, GPU, Wi-Fi):** no public Rockchip Android 11 source on GitHub (Radxa's
  manifest points at its own server). Take vendor/odm prebuilt from
  `Rock4b-android11-20220819` (Android 11, Treble), the way upstream takes the Dot's blobs
  from Fire OS. To check: Treble/VNDK version, partition layout (dynamic `super`?), and
  whether its HALs suit LineageOS 18.1's system.
- **Kernel:** Rockchip BSP 4.19 (what that vendor expects). YUPP DTS ported from the
  vendor 4.4 DTS / the Armbian rock-pi-4b delta; the BSP's DSI panel node takes the GM8775C
  init sequence from DT. Builds natively on arm64 (`linux-test`).
- **Bootloader:** the mirror boots from SD (eMMC Android is gone). Rockchip U-Boot + GPT
  image like Radxa's.
- **Mirror hardware not in the Echos:** buttons on XR20M1172 (i2c7), BCM4354 Wi-Fi/BT,
  es8388 codec, UVC camera. Never enable i2c8 (bricks boot).

## Radxa `Rock4b-android11-20220819` image (inspected 2026-10-31)

Workspace: `/Volumes/koa-build/yupp/radxa-rock4b-a11/` (`parts/` holds every partition,
`kernel-4.19.232.config` the kernel's IKCONFIG).

- **GPT, single slot:** security, uboot, trust, misc, dtbo, vbmeta, boot (40 MB), recovery
  (102 MB), backup, cache, metadata, baseparameter, super (3212 MB), userdata (grows).
- **super (LP v10):** system 938 MB, system_ext 131 MB, vendor 225 MB, product 1766 MB,
  odm 1 MB; all ext4, first-stage mounted. userdata f2fs with FBE.
- **Treble:** `ro.treble.enabled=true`, `ro.vndk.version=30`, first API 30, vendor
  `userdebug`, `RD2A.211001.002`, security patch 2021-10-01. LineageOS 18.1 is VNDK 30 too.
- **Vendor HALs:** audio 6.0 with `audio.primary.rk30board.so` (the HAL the YUPP's own
  Android used), Mali midgard gralloc 4.0, hwcomposer, camera provider incl. external (UVC),
  bluetooth 1.0, wifi 1.0 + wpa_supplicant, health, sensors, OP-TEE keymaster/gatekeeper.
  Firmware has BCM4354 (`bcm4354a1.hcd`, `BCM4354A2.hcd`, `fw_bcm4354a1_ag*.bin`).
- **boot:** header v2, kernel `4.19.232` (Android clang 11), uncompressed Image, DTB in the
  header (104 KB, `rockchip,rockpi`), Rockchip resource in `second`. cmdline has
  `androidboot.selinux=permissive`.
- **Kernel config:** built in: `BCMDHD`, Mali midgard, `ROCKCHIP_DW_MIPI_DSI`,
  `DRM_PANEL_SIMPLE`, `USB_VIDEO_CLASS`, `KEYBOARD_GPIO`, binder. Vendor modules are only
  other Wi-Fi chips (`8723cs`, `cywdhd`, …), so a rebuilt kernel needs no module rebuild for
  the mirror. **Missing for the mirror:** `SND_SOC_ES8328_I2C` (es8388 codec) and
  `SERIAL_SC16IS7XX` (XR20M1172, buttons). So the kernel must be rebuilt, not just the DTB.
- **Kernel source:** `rockchip-linux/kernel` `develop-4.19` is 4.19.232 and has
  `sound/soc/codecs/es8328*.c` and `drivers/tty/serial/sc16is7xx.c`.
- **Display:** the vendor Android DTB drove the panel with a BSP `simple-panel-dsi` node
  (timings + 35-write init sequence), which the 4.19 BSP still has, so the GM8775C should
  need DT only (no driver patch) on this kernel.

## The mirror's own Android 7.1.2 (eMMC dump, 2026-05-22)

Dump: `/Volumes/Temp/Recording/emmc-20260522-final/` (NAS, `MANIFEST.md` has sha256s and the
by-name map). `resource` = `mmcblk1p4`; its `rk-kernel.dtb` is copied with the decompiled
`rk-kernel.dts` to `/Volumes/koa-build/yupp/vendor-a7/`.

- **Display:** `dsi@ff960000/panel@0`, `simple-panel-dsi`, `mipi_type = "gm8775c"`, 4 lanes,
  `dsi,flags = 0xa03`, init sequence in `panel-init-sequence-gm8775c` (the vendor kernel
  picked the property by `mipi_type`; the 4.19 BSP reads `panel-init-sequence`).
- **Audio:** `es8388@10` on i2c, `everest,es8388`. 4.19 needs `SND_SOC_ES8328_I2C`.
- **Buttons:** `xrm117x@30` on i2c7 (`exar,xrm117x`, a vendor driver). Not needed:
  Radxa's kernel has `I2C_CHARDEV=y` and `INPUT_UINPUT=y`, so a small daemon can read the
  XR20M1172 over `/dev/i2c-7` (as yuppd does) and send keys through uinput.
- **Wi-Fi:** `wireless-wlan`, `wifi_chip_type = "ap6354"` (BCM4354), the same platdata
  style the Radxa bcmdhd uses.

So the only kernel change the first boot needs is **`SND_SOC_ES8328_I2C=y`**, plus the YUPP DTB.

## Build size

LineageOS 18.1 for one device: shallow sync ~70 GB + out ~60–80 GB, within the 238 GiB
`koa-build` SSD (upstream's ">100 GB" includes ccache). Host: x86_64 container under
Rosetta (`container run --arch amd64`), 16 GB RAM, so few jobs and swap.

## Open questions

1. ~~Radxa image layout~~ (done, above). Still open: does LineageOS 18.1's system boot on
   this vendor (VNDK matches; HAL versions and SELinux to check on the first boot).
2. A recovery for OTA: TWRP for RK3399, or a small updater of our own (`twrp-update.sh` is
   the only Echo-bound piece of the OTA path).
3. Echo cancellation for the mirror (no FPGA reference; Rockchip HAL loopback or software).
