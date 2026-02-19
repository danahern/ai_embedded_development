# Alif E7 ADB Gadget

Status: In-Progress
Created: 2026-02-17

## Problem

The STM32MP1 ADB gadget is complete and provides zero-config USB developer access (`adb shell`, `adb push/pull`, `adb forward`). The Alif E7 needs the same workflow but has a different USB controller (DWC3 vs DWC2), kernel recipe (`linux-alif` vs `linux-stm32mp`), and uses `DISTRO = "poky"` (not Alif's `apss-tiny`), so the `apss-usb` DISTRO_FEATURE that auto-includes USB gadget config won't activate.

## Approach

Extend the existing meta-eai layer with E7 support. The gadget script already auto-detects UDC (`ls /sys/class/udc/`), so it's board-agnostic. Only the kernel bbappend and product strings need E7 variants. ADB-only first (same proven pattern as STM32MP1).

## Solution

### Kernel Config (meta-eai)

New `linux-alif_%.bbappend` with `usb-gadget-adb.cfg` fragment. The fragment requests DWC3 + gadget + FunctionFS, but the E7 `devkit_e8_defconfig` already enables all USB support as built-in (`=y`). Our fragment acts as a safety net — if the defconfig changes, our config ensures USB gadget support remains.

### Board-Aware Gadget Script

Updated `usb-ecm.sh` to detect board via `/proc/device-tree/model`:
- Alif boards: serial `eai-alif-e7-001`, product `Alif E7 Dev Board`
- STM32MP1 (default): serial `eai-stm32mp1-001`, product `STM32MP1 Dev Board`

UDC auto-detection works for both DWC2 and DWC3.

### RDEPENDS

`usb-ecm_1.0.bb` base RDEPENDS is just `busybox`. Kernel module deps are STM32MP1-only via machine override (`RDEPENDS:${PN}:append:stm32mp1`), since E7 builds USB gadget support as built-in, not modules.

### Build Config

- `bblayers.conf`: Added `meta-eai` + `meta-networking` (required by `meta-filesystems`)
- `local.conf`: Added Alif BSP source URLs (`ALIF_KERNEL_TREE`, `TFA_TREE`, etc.), ADB packages, `BB_DANGLINGAPPENDS_WARNONLY`

## Implementation Notes

### Build discoveries

- **Alif BSP source variables not auto-set**: `ALIF_KERNEL_TREE`, `ALIF_KERNEL_BRANCH`, `TFA_TREE`, `TFA_BRANCH`, `LINUX_DD_TC_TREE`, `LINUX_DD_TC_BRANCH` are only auto-configured by the `apss-tiny` distro's setup script. When using `poky` distro, these must be set in `local.conf`. Values found in the [scarthgap build-setup repo](https://github.com/alifsemi/alif_linux-apss-build-setup).
- **Kernel repo is `linux_alif`** (not `alif_linux`): The scarthgap branch uses different repo names than the older 5.4 setup.
- **meta-networking required**: `meta-filesystems` depends on `meta-networking`. Not included in original bblayers.conf.
- **Dangling bbappends**: `linux-stm32mp_%.bbappend` (meta-eai) and `tensorflow-lite_%.bbappend` (meta-alif) have no matching recipes in E7 build. Fixed with `BB_DANGLINGAPPENDS_WARNONLY = "true"`.
- **DWC3 built-in, not module**: The `devkit_e8_defconfig` builds all USB support as `=y`. Our config fragment's `=m` values get overridden by defconfig's `=y`. This means no `kernel-module-dwc3` packages exist — RDEPENDS must not reference them.
- **Kernel fetch timeout**: Bitbake's fetcher timed out cloning the Linux kernel repo. Pre-cloning into `downloads/git2/` directory resolved it.

### Files Modified (Docker volume)

| File | Change |
|------|--------|
| `meta-eai/recipes-kernel/linux/linux-alif_%.bbappend` | **New** — kernel config fragment for USB gadget |
| `meta-eai/recipes-kernel/linux/files/usb-gadget-adb.cfg` | **New** — DWC3 + gadget + FunctionFS config |
| `meta-eai/recipes-connectivity/usb-ecm/files/usb-ecm.sh` | Board detection via /proc/device-tree/model |
| `meta-eai/recipes-connectivity/usb-ecm/usb-ecm_1.0.bb` | Machine-conditional module RDEPENDS (STM32MP1 only) |

### Files Modified (workspace)

| File | Change |
|------|--------|
| `yocto-build/build-alif-e7/conf/bblayers.conf` | Added meta-eai + meta-networking |
| `yocto-build/build-alif-e7/conf/local.conf` | BSP source URLs, ADB packages, danglingappends |
| `plans/alif-e7-linux.md` | Updated Phase 4 status |
| `firmware/linux/alif-e7/README.md` | Added ADB section |

## Verification

- [x] `bitbake core-image-minimal` succeeds (3384/3384 tasks)
- [x] xipImage includes DWC3 + FunctionFS support (both `=y` in .config)
- [x] adbd + usb-ecm.sh + init script present in rootfs
- [ ] On hardware: gadget script auto-detects DWC3 UDC (requires SETOOLS first boot — see `plans/alif-e7-setools.md`)
- [ ] `adb devices` on Mac sees `eai-alif-e7-001`
- [ ] `adb shell` works

## Modifications

- Dropped `kernel-module-dwc3` RDEPENDS — E7 defconfig builds USB as built-in
- Added `meta-networking` to bblayers (meta-filesystems dependency)
- Added Alif BSP source URL variables to local.conf (not set by poky distro)
- Added `BB_DANGLINGAPPENDS_WARNONLY` for cross-board bbappend compatibility
- Pre-cloned Alif kernel/TFA repos to work around bitbake fetch timeout
- TF-A (`bl32.bin`) and cramfs-xip rootfs not built by poky distro — added to local.conf in SETOOLS plan (`plans/alif-e7-setools.md`)
