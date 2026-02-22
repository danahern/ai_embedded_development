# Alif Ensemble E7 Linux Support

Status: In-Progress
Created: 2026-02-17

## Problem

The workspace has mature embedded Linux infrastructure for STM32MP1 (Yocto image builds, Buildroot cross-compilation, Docker containers, linux-build MCP). The Alif E7 DevKit (2x Cortex-A32 + 2x Cortex-M55 + Ethos-U55 NPU) needs the same workflow: Yocto image build, app cross-compilation, deploy/SSH.

Key differences from STM32MP1: proprietary boot chain (SE → TFA → kernel, no U-Boot), XIP kernel from MRAM, Cortex-A32 (vs A7).

## Approach

### Evolution

The build setup went through three iterations:

1. **scarthgap + devkit-e7** — Initial attempt. `devkit-e7.conf` was archived as `.orig` in scarthgap.
2. **scarthgap + appkit-e8** — Second attempt. Builds completed but: wrong kernel (v6.12-dev has no working E7 DTS), wrong TF-A branch (`lts-v2.10.8` uses different variable names like `AP_HYPERRAM_EN`), and scarthgap has no `appkit-e7.conf`.
3. **zeus + appkit-e7 via orchestrator** — Correct approach. Official `alifsemi/alif_linux-apss-build-setup` pulls OE zeus, kernel 5.4.25, and TF-A `devkit-ex-b0`. Linux boots successfully.

### Current: Official Orchestrator (zeus)

Uses `apss/ubuntu-builder:v18.04` Docker image with the official `alifsemi/alif_linux-apss-build-setup` orchestrator. The orchestrator clones all layers at correct branches and generates `auto.conf` with:
- `MACHINE = "appkit-e7"` (from `meta-alif-ensemble` branch `devkit-ex-b0`)
- `DISTRO = "apss-tiny"` (musl + poky-tiny + busybox)
- `ALIF_KERNEL_BRANCH = "devkit-b0-5.4.y"` (kernel 5.4.25)
- `TFA_BRANCH = "devkit-ex-b0"`

Customizations in `local.conf`: parallelism limits (`-j4`), optional DISTRO_FEATURES.

## Solution

### Docker Infrastructure
- **Image**: `apss/ubuntu-builder:v18.04` (official Alif image, NOT our `yocto-builder`)
- **Container**: `alif-apss-build`
- **Volume**: `alif-apss-data` (mounted at `/home/apssbuilder/build-data`)
- **Build dir**: `/home/apssbuilder/build-data/build-appkit-e7/`
- **Layers**: `/home/apssbuilder/apss-build-setup/layers/` (openembedded-core, meta-alif, meta-alif-ensemble, meta-alif-iot, meta-openembedded, meta-yocto)

### Build Artifacts
| File | Size | Description |
|------|------|-------------|
| `bl32.bin` | ~30KB | TF-A BL32 Secure Payload |
| `xipImage` | ~2.1MB | XIP kernel (runs from MRAM) |
| `appkit-e7.dtb` | ~25KB | Device tree blob |
| `alif-tiny-image-appkit-e7.cramfs-xip` | ~1.3MB | Read-only rootfs |
| **Total** | **~3.5MB** | MRAM capacity: 5.7MB |

### Cross-Compilation
- `firmware/linux/docker/Dockerfile.alif-e7` — Ubuntu 22.04 + `crossbuild-essential-armhf`
- System cross-compiler: `arm-linux-gnueabihf-gcc` (no Buildroot dependency)
- CPU flags: `-mcpu=cortex-a32 -mfpu=neon -mfloat-abi=hard`

### Board-Aware Makefiles
- `BOARD` variable in each app Makefile
- `BOARD=alif-e7`: system cross-compiler + Cortex-A32 flags
- Default (no BOARD): existing Buildroot toolchain + Cortex-A7 flags

## Implementation Notes

- **Machine config naming**: `appkit-e7.conf` exists on `devkit-ex-b0` branch. Scarthgap has only `appkit-e8.conf` (targets different hardware vars). Always use `devkit-ex-b0` branch for E7 AppKit.
- **auto.conf vs local.conf**: The orchestrator generates `auto.conf` with MACHINE, DISTRO, and BSP URLs. Our `local.conf` has customizations only (parallelism, optional features). Do NOT set MACHINE/DISTRO in local.conf.
- **zeus syntax**: Use `_append`/`_remove` (NOT `:append`/`:remove`). `CONF_VERSION = "1"` (NOT "2").
- **meta-eai layer excluded**: Our custom meta-eai uses scarthgap override syntax (`:` instead of `_`). Not compatible with zeus. USB gadget and display config fragments need porting to zeus syntax before inclusion.
- **Kernel repo naming**: zeus uses `alif_linux` (not `linux_alif`). TF-A repo is `alif_arm-tf` (not `trusted-firmware-a_alif`).
- **DTB naming**: Machine config produces `appkit-e7.dtb`. If it causes kernel panic (wrong compatible string), override with `KERNEL_DEVICETREE = "appkit-e7-flatboard.dtb"` in local.conf.
- **Rootfs address**: `0x80300000` for E7 AppKit (NOT `0x80380000` which is E8).

### Files Created
- `yocto-build/build-alif-e7/conf/bblayers.conf`
- `yocto-build/build-alif-e7/conf/local.conf`
- `firmware/linux/docker/Dockerfile.alif-e7`
- `firmware/linux/alif-e7/README.md`
- `firmware/linux/alif-e7/setools/flash-e7.sh`
- `firmware/linux/alif-e7/setools/linux-boot-e7.json`
- `knowledge/boards/alif_e7_devkit.yml`

### Files Modified
- `firmware/linux/apps/hello/Makefile` — added BOARD=alif-e7 support
- `firmware/linux/apps/rpmsg_echo/Makefile` — added BOARD=alif-e7 support
- `firmware/linux/apps/Makefile` — passes BOARD= to sub-makes
- `firmware/linux/README.md` — covers both STM32MP1 and E7

### Knowledge Items Captured
- E7 AppKit requires devkit-ex-b0 branch (not scarthgap)
- meta-alif requires meta-filesystems
- E7 XIP boot chain (SE → TFA → xipImage)
- Cortex-A32 vs A7 cross-compilation flags
- Yocto OOM on Apple Silicon Docker
- SETOOLS baud rate (57600, not 55000)
- Power cycle required after SETOOLS flash

## Verification

- [x] `bitbake alif-tiny-image` completes without error
- [x] `bl32.bin`, `xipImage`, DTB, and cramfs-xip all present in deploy dir
- [x] cramfs-xip under 2MB (1.3MB — fits in MRAM)
- [x] Flash all images via `alif-flash` MCP / flash-e7.sh
- [x] Power cycle → TF-A banner → kernel boot → login prompt on UART2
- [x] `root` login works, busybox shell functional
- [ ] meta-eai layer ported to zeus syntax (deferred — not needed for base image)
- [ ] ADB over USB validated on hardware
