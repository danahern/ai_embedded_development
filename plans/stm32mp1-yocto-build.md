# STM32MP1 Yocto Build

Status: Complete
Created: 2026-02-17

## Problem

The current STM32MP1 DK1 runs a pre-built OpenSTLinux image from ST. We can cross-compile and deploy user-space apps via SSH, but cannot customize the kernel, add kernel modules, create custom sysfs entries, or modify the root filesystem layout. A Yocto build gives us full control over the Linux side.

## Approach

Build a minimal Yocto image using upstream layers on the **scarthgap** branch (Yocto 5.0 LTS). Start with `core-image-minimal` to verify boot, then extend with custom layers/packages.

**Layers:**
- `poky` (scarthgap) — Yocto reference distribution
- `meta-openembedded` (scarthgap) — meta-oe + meta-python
- `meta-st-stm32mp` (scarthgap) — ST BSP for STM32MP1

**MACHINE:** `stm32mp1`
**Image:** `core-image-minimal` (small, fast build, boots to shell)

**Build environment:** Docker container (Ubuntu 22.04) with Docker named volume (case-sensitive filesystem required by Yocto).

## Solution

### Docker Setup
- Dockerfile at `firmware/linux/yocto/Dockerfile`
- Docker image: `yocto-builder`
- Docker named volume: `yocto-data` (case-sensitive, avoids macOS case-insensitive issue)
- Bind mount: `yocto-build/` → `/home/builder/artifacts` (for copying images to host)
- Non-root user `builder` (Yocto refuses to build as root)

### Build Commands
```bash
# Start container
docker run -dit --name yocto-build \
  -v yocto-data:/home/builder/yocto \
  -v /Users/danahern/code/claude/work/yocto-build:/home/builder/artifacts \
  yocto-builder

# Inside container:
cd /home/builder/yocto
source poky/oe-init-build-env build-stm32mp
bitbake core-image-minimal
```

### Key Config (local.conf)
```
MACHINE = "stm32mp1"
ACCEPT_EULA_stm32mp1 = "1"
BB_NUMBER_THREADS = "4"
PARALLEL_MAKE = "-j 4"
BOOTDEVICE_LABELS = "sdcard"
BOOTSCHEME_LABELS = "opteemin"
STM32MP_DT_FILES_SDCARD = "stm32mp157d-dk1 stm32mp157c-dk2"
WKS_IMAGE_FSTYPES += "wic wic.bz2 wic.bmap"
WKS_FILE = "sdcard-stm32mp157f-dk2-opteemin-example.wks.in"
IMAGE_FEATURES += "ssh-server-dropbear"
```

### Flashing to SD Card
```bash
# Decompress and flash (on macOS, find SD card device with diskutil list)
diskutil unmountDisk /dev/diskN
bzcat yocto-build/core-image-minimal-stm32mp1.wic.bz2 | sudo dd of=/dev/rdiskN bs=4m
```

### Custom Layer: meta-eai
Inside Docker volume at `/home/builder/yocto/meta-eai/`:
- `recipes-connectivity/usb-ecm/` — USB CDC-ECM gadget with DHCP server
- Auto-starts at boot via SysVinit (S90usb-ecm)
- Fixed MAC addresses for consistent networking
- DHCP assigns 192.168.7.1 to macOS host

### Output
- WIC image: `yocto-build/core-image-minimal-stm32mp1.wic.bz2` (20MB compressed, ~1GB raw)
- Includes: TF-A, OP-TEE, U-Boot, Linux 6.6, kernel modules, USB gadget networking, Dropbear SSH

## Implementation Notes

- **Case-sensitive filesystem required**: macOS is case-insensitive by default. Docker bind mounts inherit host FS. Must use a Docker named volume for the build tree.
- **OOM on GCC cross-compile**: gimple-match.cc needs 4GB+ to compile. Docker Desktop defaults to ~8GB. Keep parallelism at -j 4 / BB_NUMBER_THREADS=4.
- **gcc-multilib unavailable on ARM64**: Not needed — Yocto builds its own cross-toolchain. Remove from Dockerfile.
- **WKS_FILE not set by stm32mp1 machine**: Must explicitly set in local.conf. DK1 and DK2 share the same SD card layout.
- **BusyBox head syntax**: `head -1` is invalid in BusyBox — must use `head -n 1`.
- **configfs not auto-mounted**: Must `mount -t configfs none /sys/kernel/config` before creating USB gadgets.
- **kernel-modules package**: `core-image-minimal` doesn't include kernel modules by default. Add `IMAGE_INSTALL:append = " kernel-modules"` to local.conf.
- **Yocto recipe WORKDIR vs UNPACKDIR**: In scarthgap, `file://` SRC_URI files land in `WORKDIR`, not `UNPACKDIR`. Use `${WORKDIR}` in `do_install()`.
- **First build ~40 min** (on M3 Max with -j 4). Incremental rebuilds use sstate cache and are much faster (~2 min for rootfs changes).
- **Build tree is ~30GB** inside the Docker volume.

## Modifications

- Skipped flashlayout method (not generated for core-image-minimal). WIC image is the simpler direct approach.
- Limited to sdcard boot + opteemin scheme to speed up build.
- Only building DK1 + DK2 device trees (skipped eval boards).

## Verification

- [x] Docker container builds and runs
- [x] Yocto layers cloned and configured
- [x] bitbake core-image-minimal completes (4449 tasks, all succeeded)
- [x] SD card image produced (WIC: core-image-minimal-stm32mp1.wic.bz2)
- [x] Board boots from new image (TF-A → OP-TEE → U-Boot → Linux 6.6.78)
- [x] USB CDC-ECM gadget networking works (ping + DHCP auto-config)
- [x] SSH works on new image (Dropbear, root@192.168.7.2)
