# YUPP mirror (SMDT AIoT-3399X, RK3399)

Goal: an integrated Android image for the YUPP BM-S-21E1 mirror, in the style of
[lineageos-echo-kiosk-satellite](https://github.com/jxlarrea/lineageos-echo-kiosk-satellite):
Kiosk Satellite installed on first boot as device owner, setup from adb, system updates.

Board reference: `~/Projects/armbian-yupp-aiot3399x` (DTS as a rock-pi-4b delta, GM8775C
DSI→LVDS display, es8388 audio, BCM4354 Wi-Fi/BT, buttons on XR20M1172/i2c7, never i2c8).
Kiosk Satellite needs Android 7.0 or newer.

## Base options (2026-10-31)

| | GloDroid (AOSP 13/14) | Radxa Rock Pi 4B Android 11 (prebuilt, modified) |
|---|---|---|
| RK3399 status | Stale: `rockchip-series` 2023-05, PinePhone Pro 2023-08 | `Rock4b-android11-20220819`; Rock 4C Plus build 2024-12 |
| Kernel | Mainline (reuse the 6.18 DTS and GM8775C patches) | Rockchip BSP 4.19 (vendor Android 7.1.2 ran BSP 4.4 with this panel) |
| Build | Full AOSP tree: ~180–250 GB, x86_64 host (Rosetta), 16 GB RAM is tight | No AOSP build: unpack the image, swap kernel/DTB, add the KS layer to system/vendor; kernel builds natively on arm64 (`linux-test`) |
| Disk | ~200+ GB | ~20–30 GB |
| Android version | 13/14 | 11, the same as the Echo images, so their KS layer maps over |

## Chosen: a new device in upstream's LineageOS 18.1 tree

To keep upstream's layer untouched, the mirror becomes one more device of
lineageos-echo-kiosk-satellite, with Radxa's Android 11 vendor taken prebuilt. See
[ANALYSIS.md](ANALYSIS.md). The section below was the earlier, image-only idea.

## Earlier idea: modify the Radxa Android 11 image

1. Boot the stock `Rock4b-android11-20220819` image on the mirror (SD card), see what works
   (display needs the YUPP DTS, so expect a black panel; HDMI/adb first).
2. Build the Radxa 4.19 kernel with a YUPP DTS: the BSP's DSI panel node takes the GM8775C
   init sequence from DT, and its lane-rate math is the vendor's.
3. Repack boot/resource with the new kernel and DTB.
4. Add the KS layer to the system image: first-boot installer, device owner, permissions,
   settings defaults, a device command (`yupp_service`), signed updates.
5. Port audio tuning facts (volume curve, codec levels) from the Armbian repo's AGENTS.md.

## State (2026-11-01)

The mirror boots Radxa's Android 11 on our kernel with its own tree, from a cold start,
reachable over Wi-Fi adb (port 5555) and USB OTG adb. Display 1920x1080 (GM8775C),
es8388, AC108 USB mics, GPU, USB camera and Wi-Fi (BCM4354) work.

- **Boot:** Rockchip's U-Boot stops on any modified rk-kernel.dtb, so the boot partition holds
  Radxa's DTB and `loader/init`, which kexecs the same kernel with `dts/rk3399-yupp-android.dts`
  twice: first with itself again, so the display comes up, then with Android's ramdisk (one
  kexec sometimes left the panel on its self-test pattern; this one has worked on the first
  boot, while repeated cold boots have not been checked yet). The boot image's command line
  has `video=DSI-1:d video=DSI-2:d` so the loader kernel leaves the display alone; the loader
  strips it. Built with `scripts/repack-boot.py … --ramdisk=loader.cpio.gz --cmdline-append=…`.
- **Kernel:** `scripts/build-kernel.sh` (Radxa IKCONFIG + ES8328_I2C + KEXEC + DEVMEM),
  `scripts/build-modules.sh` for `bcmdhd.ko` (Wi-Fi; the vendor's was built for Radxa's kernel).
  On the mirror it is in /vendor/lib/modules through `adb remount` (overlayfs) for now.
- **Bring-up without a serial console:** `scripts/kexec-try.sh` (try a kernel/tree/ramdisk from
  the running Android; a hang is undone by a power cycle), `scripts/otg-try.sh` (an image in
  recovery, booted once through U-Boot with `diag/reboot-to recovery`), `diag/init` (writes a
  report to the backup partition). `adb reboot recovery` is not one-shot: it leaves a bootloader
  message in misc.

Done through overlays (`adb remount`) for now: portrait (`ro.surface_flinger.primary_display_orientation=ORIENTATION_270`
in /vendor/build.prop), buttons (`buttons/`, XR20M1172 over /dev/i2c-7), Kiosk Satellite
(device owner, home launcher).

To do: cold-boot checks of the two-step loader, the power button (no event on GPIO0_A5), then
a separate YUPP-mirror repo forked from lineageos-echo-kiosk-satellite (vendor taken from
Radxa, our kernel/modules, the loader, the overlays above baked in).

## First boot test (milestone 1)

Radxa's Android 11 with the mirror's kernel and device tree, nothing else changed.

| Step | Script | Output on the SSD (`/Volumes/koa-build/yupp/out/`) |
|---|---|---|
| Kernel: Radxa's IKCONFIG + `SND_SOC_ES8328_I2C` on `rockchip-linux/kernel` develop-4.19 | `scripts/build-kernel.sh` | `kernel/arch/arm64/boot/Image` |
| Device tree: `dts/rk3399-yupp-android.dts`, a delta on Radxa's decompiled `rockpi4b.dts` | `scripts/build-dtb.sh` | `rk3399-yupp-android.dtb` |
| Boot image: kernel + DTB into Radxa's boot (header dtb and resource `rk-kernel.dtb`) | `scripts/repack-boot.py` (round-trips Radxa's own boot byte for byte) | `boot-yupp.img` |
| SD image: Radxa GPT image, the mirror's own idbloader (sectors 64–4095 of its eMMC dump), the new boot | `scripts/make-sd-image.py` | `yupp-android11-test.img` |

`scripts/fdtflat.py` flattens a DTB to `path:prop = value` lines for diffing.

## Build host

- External SSD `koa-build` (256 GB, case-sensitive APFS). 2026-10-31: it dropped off USB
  mid-write in the first test (436 MB into a 1 GB write) — connection/power needs fixing
  before any large job.
- Apple `container` runs amd64 images via Rosetta (`container run --arch amd64`), checked.
