# Alif E7: R/W Filesystem + USB Gadget + ADB

Status: In-Progress (partially superseded)
Created: 2026-02-17
Updated: 2026-02-28

**2026-02-28 note**: CDC-ECM USB networking achieved on devkit-e8 via Yocto Scarthgap (separate path from this plan's OE Zeus E7 approach). Board reachable at 192.168.55.2. ADB goal deferred in favor of SSH over CDC-ECM. Original E7 MRAM kernel flash issue remains unresolved.

## Problem

Linux console is working on Alif E7 AppKit (cramfs-xip rootfs, XIP kernel 5.4.25). Need:
1. A writable filesystem (current cramfs is read-only) — tmpfs at /tmp, /var
2. ADB (Android Debug Bridge) for `adb shell`, `adb push/pull`
3. USB gadget mode for the ADB transport (DWC3 at 0x48200000)

## Approach

Rebuild kernel + rootfs via the official Alif orchestrator Docker container (`apss/ubuntu-builder:v18.04`) with:
- USB gadget kernel support (via meta-eai config fragment)
- adbd + usb-ecm packages (via meta-eai recipes)
- USB enabled in DTB (HSUSB_STATUS="okay")

**Key change from previous attempt**: Using the official orchestrator (`alifsemi/alif_linux-apss-build-setup`) with `DISTRO="apss-tiny"` and OE zeus (Yocto 3.0), NOT the scarthgap/poky approach.

## Solution

### Pre-work: OE zeus syntax fixes

meta-eai was written for scarthgap (`:` override syntax). OE zeus uses `_` syntax:

| File | Change |
|------|--------|
| `meta-eai/conf/layer.conf` | `LAYERSERIES_COMPAT` → `"zeus"` |
| `meta-eai/recipes-kernel/linux/linux-alif_%.bbappend` | `FILESEXTRAPATHS:prepend` → `FILESEXTRAPATHS_prepend` |
| `meta-eai/recipes-connectivity/usb-ecm/usb-ecm_1.0.bb` | `RDEPENDS:` → `RDEPENDS_`, module deps moved to devkit-e8 only |
| `meta-eai/recipes-devtools/android-tools-conf/android-tools-conf_1.0.bb` | `RPROVIDES:` → `RPROVIDES_`, `ALLOW_EMPTY:` → `ALLOW_EMPTY_` |

### USB config: built-in instead of modules

Changed `usb-gadget-adb.cfg`: `CONFIG_USB_LIBCOMPOSITE=y` and `CONFIG_USB_FUNCTIONFS=y` (were `=m`). Saves rootfs space — no .ko files needed. Base RDEPENDS is just `busybox`.

### DTS: USB enabled

Changed `alif_linux/arch/arm/boot/dts/appkit_ex_dct_defines.h`: `HSUSB_STATUS` → `"okay"`. DTB recompiled separately from source.

### Docker build config

- Container: `alif-apss-build` (image `apss/ubuntu-builder:v18.04`, volume `alif-apss-data`)
- Orchestrator auto-generates `auto.conf` with `MACHINE="devkit-e7"`, `DISTRO="apss-tiny"`, correct BSP branches
- meta-eai copied into container at `/home/apssbuilder/apss-build-setup/layers/meta-eai`
- `bblayers.conf`: All orchestrator layers + meta-eai
- `local.conf`: `IMAGE_INSTALL_append = " android-tools usb-ecm"`, `BB_NUMBER_THREADS=4`, `PARALLEL_MAKE="-j 4"`, `BB_DANGLINGAPPENDS_WARNONLY`

## Implementation Notes

### Build setup discoveries (2026-02-22)

- **Orchestrator creates `build/` by default**: Pass `build-alif-e7` as arg to setup.sh for named build dir
- **setup.sh runs bitbake-layers add-layer**: Some layers failed to add (meta-alif-ensemble, meta-filesystems, meta-poky) — dependency issues. Fixed by writing bblayers.conf directly.
- **Build dir created as root**: `docker exec` defaults to root, but bitbake refuses to run as root. Must `chown -R apssbuilder:apssbuilder` and `docker exec -u apssbuilder`.
- **Package name is `android-tools`**: Zeus recipe `android-tools_5.1.1.r37.bb` bundles adbd into the main package. No separate `android-tools-adbd` split package in this version.
- **picoclaw recipe also needed zeus syntax fix**: `INSANE_SKIP:`, `FILES:`, `CONFFILES:` → `_` syntax.
- **yocto_build MCP tool incompatible**: Hardcodes `/home/builder/yocto` and `poky/oe-init-build-env`. Alif orchestrator uses `/home/apssbuilder/apss-build-setup/` and `openembedded-core/oe-init-build-env`. Must use `run_command` or `docker exec` directly.

### Files Modified (workspace)

| File | Change |
|------|--------|
| `firmware/linux/yocto/meta-eai/conf/layer.conf` | `LAYERSERIES_COMPAT` → `"zeus"` |
| `firmware/linux/yocto/meta-eai/recipes-kernel/linux/linux-alif_%.bbappend` | Zeus `_` syntax |
| `firmware/linux/yocto/meta-eai/recipes-kernel/linux/files/usb-gadget-adb.cfg` | LIBCOMPOSITE + FUNCTIONFS → `=y` |
| `firmware/linux/yocto/meta-eai/recipes-connectivity/usb-ecm/usb-ecm_1.0.bb` | Zeus syntax, module deps → devkit-e8 only |
| `firmware/linux/yocto/meta-eai/recipes-devtools/android-tools-conf/android-tools-conf_1.0.bb` | Zeus `_` syntax |
| `alif_linux/arch/arm/boot/dts/appkit_ex_dct_defines.h` | `HSUSB_STATUS` → `"okay"` |
| `yocto-build/build-alif-e7/conf/bblayers.conf` | Added meta-eai layer |
| `yocto-build/build-alif-e7/conf/local.conf` | Uncommented adbd + usb-ecm |

## OSPI Boot (2026-02-22)

First build with USB + ADB succeeded (1554 tasks) but artifacts exceeded MRAM:
- xipImage: 3.16MB (MRAM slot: 2.875MB)
- rootfs: 6.3MB (MRAM slot: 2MB)

### Solution: OSPI boot

Move kernel XIP + rootfs from MRAM to OSPI1 NOR flash (0xC0000000+, 32-64MB capacity).

**Config changes** (`local.conf`):
```
OSPI_BOOT = "1"
KERNEL_MTD_LEN = "0x700000"
```

`OSPI_BOOT=1` triggers `devkit-e7.conf` to include `ospi-config.inc`, which sets:
- `FLASH_EN=1` — enables OSPI in TF-A
- `XIP_KERNEL_LOAD_ADDR=0xC0800000` — kernel XIP from OSPI
- `KERNEL_MTD_START_ADDR=0xC0000000` — rootfs from OSPI
- `KERNEL_MTD_LEN=0x400000` (default, we override to 0x700000 for 7MB)

TF-A rebuilds with `PRELOADED_BL33_BASE=0xC0800000`.

**Key discovery**: MACHINE is `devkit-e7` (not `appkit-e7`), so the `OSPI_BOOT` conditional works natively. No need for `MX_FLASH_EN` (doesn't exist in this BSP).

### OSPI flash layout

| Component | Address | Size | Medium |
|-----------|---------|------|--------|
| TF-A (bl32.bin) | 0x80002000 | 29KB | MRAM |
| DTB | 0x80010000 | 33KB | MRAM |
| Rootfs (cramfs-xip) | 0xC0000000 | 6.3MB | OSPI1 NOR |
| Kernel (xipImage) | 0xC0800000 | 3.0MB | OSPI1 NOR |

### Build artifacts

`yocto-build/build-alif-e7/output/`:
- `bl32.bin` (29KB) — TF-A with OSPI addresses
- `devkit-e7.dtb` (33KB)
- `xipImage` (3.0MB)
- `rootfs.cramfs-xip` (6.3MB)

## MRAM-Only Rebuild (2026-02-22, session 2)

OSPI boot blocked: J-Link cannot write to OSPI addresses, SE-UART ISP can't either. Need to boot Linux from MRAM first, then program OSPI via MTD from Linux.

**Problem**: MRAM had oversized USB/ADB kernel (3.01MB) that wouldn't boot. Needed to rebuild minimal MRAM-fitting images.

**Root cause of persistent 3.01MB kernel**: Bitbake caches the kernel `.config`. Commenting out a config fragment in `SRC_URI` does NOT regenerate `.config` — must run `bitbake linux-alif -c cleansstate` first. Additionally, the base defconfig has `# CONFIG_USB_SUPPORT is not set` and `# CONFIG_DRM is not set`, so ALL USB and DRM came from our fragments.

**Result after cleansstate + both fragments disabled**:
- Kernel: 2,851,324 bytes (2.72MB) — fits 2.875MB slot
- Rootfs: 1,998,848 bytes (1.9MB) — fits 2.5MB slot
- TF-A: 30,136 bytes — already had MRAM addresses (PRELOADED_BL33_BASE=0x80020000)

**Flash result**: TFA, DTB, rootfs all flashed and verified OK via `jlink_flash`. **Kernel write consistently fails** at address 0x802D81F0 (12 bytes from end, 2.85MB offset). First attempt: loadbin succeeds but verify fails. Subsequent attempts: loadbin itself fails ("Writing target memory failed"). Persists across power cycles. See knowledge item k-80cfe850.

**Next steps**:
1. Investigate MRAM write failure (firewall? JLink buffer limit? Try smaller chunks or different AP)
2. Once MRAM boot works: check for OSPI MTD from Linux
3. Program OSPI from Linux, switch to OSPI boot, re-enable USB+DRM fragments

## Verification

- [x] `bitbake alif-tiny-image` succeeds (1568 tasks, OSPI config)
- [x] TF-A rebuilt with `PRELOADED_BL33_BASE=0xC0800000`, `FLASH_EN=1`
- [x] Rootfs (6.3MB) fits in 7MB KERNEL_MTD_LEN
- [x] MRAM-only rebuild: kernel 2.72MB, rootfs 1.9MB (both fit)
- [x] TFA/DTB/rootfs flash + verify OK via jlink_flash
- [ ] **BLOCKED**: Kernel flash fails at 0x802D81F0 — needs investigation
- [ ] Flash TF-A + DTB to MRAM, rootfs + kernel to OSPI via jlink_flash
- [ ] TF-A boots and jumps to kernel at 0xC0800000
- [ ] Kernel mounts cramfs-xip rootfs from 0xC0000000
- [ ] `/sys/class/udc/` shows DWC3 UDC
- [ ] tmpfs mounts present (`/tmp`, `/var`)
- [ ] USB gadget configures ADB on USB-C
- [ ] `adb devices` on Mac sees device
- [ ] `adb shell` works
