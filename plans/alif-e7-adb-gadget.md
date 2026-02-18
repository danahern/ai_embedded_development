# Alif E7 ADB Gadget

Status: In-Progress
Created: 2026-02-17

## Problem

The STM32MP1 ADB gadget is complete and provides zero-config USB developer access (`adb shell`, `adb push/pull`, `adb forward`). The Alif E7 needs the same workflow but has a different USB controller (DWC3 vs DWC2), kernel recipe (`linux-alif` vs `linux-stm32mp`), and uses `DISTRO = "poky"` (not Alif's `apss-tiny`), so the `apss-usb` DISTRO_FEATURE that auto-includes USB gadget config won't activate.

## Approach

Extend the existing meta-eai layer with E7 support. The gadget script already auto-detects UDC (`ls /sys/class/udc/`), so it's board-agnostic. Only the kernel bbappend and product strings need E7 variants. ADB-only first (same proven pattern as STM32MP1).

## Solution

### Kernel Config (meta-eai)

New `linux-alif_%.bbappend` with `usb-gadget-adb.cfg` fragment enabling:
- DWC3 controller + gadget mode + OF simple + Ensemble platform driver
- USB gadget subsystem + libcomposite (module) + FunctionFS (module)

This covers both base USB gadget support (normally from `usb.cfg` via apss-usb distro feature) AND FunctionFS for ADB in a single fragment.

### Board-Aware Gadget Script

Updated `usb-ecm.sh` to detect board via `/proc/device-tree/model`:
- Alif boards: serial `eai-alif-e7-001`, product `Alif E7 Dev Board`
- STM32MP1 (default): serial `eai-stm32mp1-001`, product `STM32MP1 Dev Board`

UDC auto-detection works for both DWC2 and DWC3.

### Machine-Conditional RDEPENDS

`usb-ecm_1.0.bb` now has:
```
RDEPENDS:${PN}:append:devkit-e8 = " kernel-module-dwc3 kernel-module-dwc3-of-simple"
```

### Build Config

- `bblayers.conf`: Added `/home/builder/yocto/meta-eai`
- `local.conf`: Added `android-tools-adbd usb-ecm` to IMAGE_INSTALL + android-tools-conf provider

## Implementation Notes

### Files Modified (Docker volume)

| File | Change |
|------|--------|
| `meta-eai/recipes-kernel/linux/linux-alif_%.bbappend` | **New** — kernel config for USB gadget + FunctionFS |
| `meta-eai/recipes-kernel/linux/files/usb-gadget-adb.cfg` | **New** — DWC3 + gadget + FunctionFS config |
| `meta-eai/recipes-connectivity/usb-ecm/files/usb-ecm.sh` | Board detection via /proc/device-tree/model |
| `meta-eai/recipes-connectivity/usb-ecm/usb-ecm_1.0.bb` | DWC3 module RDEPENDS for devkit-e8 |

### Files Modified (workspace)

| File | Change |
|------|--------|
| `yocto-build/build-alif-e7/conf/bblayers.conf` | Added meta-eai layer |
| `yocto-build/build-alif-e7/conf/local.conf` | Added adbd + usb-ecm packages |
| `plans/alif-e7-linux.md` | Updated Phase 4 status |
| `firmware/linux/alif-e7/README.md` | Added ADB section |

### Risks

- **adbd on BusyBox init**: `update-rc.d` creates `/etc/rc*.d/` symlinks. BusyBox init + initscripts should call these, but hasn't been tested on E7.
- **DWC3 module naming**: Exact names (`kernel-module-dwc3`, `kernel-module-dwc3-of-simple`) depend on kernel build. May need adjustment.
- **CONFIG_USB_DWC3_ENSEMBLE**: This is the Alif-specific platform driver. If the config symbol name differs in the actual kernel, the fragment will need updating.

## Verification

- [ ] `bitbake core-image-minimal` succeeds with E7 build config
- [ ] xipImage includes DWC3 + FunctionFS support
- [ ] On hardware: gadget script auto-detects DWC3 UDC
- [ ] `adb devices` on Mac sees `eai-alif-e7-001`
- [ ] `adb shell` works

## Modifications

- None yet — awaiting build validation
