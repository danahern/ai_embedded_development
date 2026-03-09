# Plan: Enable ADB over USB on Alif E7 Linux

**Status:** Complete

## Context

The Alif E7 AppKit runs Linux from OSPI with a DWC3 USB controller on the SoC USB port (J2, Micro-B). All infrastructure for ADB exists in meta-eai:
- Kernel config: `usb-gadget-adb.cfg` (DWC3 gadget + ConfigFS + FunctionFS) — already in bbappend
- DTB: `dwc3-drd` node with `status = "okay"`, `dr_mode = "peripheral"` — already enabled
- Gadget scripts: `usb-ecm.sh` with ADB support (auto-detects adbd, mounts FunctionFS) — already in IMAGE_INSTALL
- Init script: `usb-ecm-init` (SysVinit S90) — already installed
- `adbd` binary already in rootfs at `/usr/bin/adbd`

## Solution

Three changes were needed to make ADB work:

### 1. DWC3 USB DTS workaround (appkit-e7.dts)
The DWC3 glue driver (`dwc3-ensemble.c`) fails to probe because the kernel clock provider (`psclks`) can't register — the MHU→SE host services chain isn't working. TF-A already enables USB clocks (CGU bits 21-23, PERIPH_CLK_ENA = 0x11111113) before jumping to Linux.

Fix: Remove clock/PHY dependencies from the DTS via `/delete-property/`:
```dts
&hsusb {
    /delete-property/ clocks;
    /delete-property/ clock-names;
    dwc3: usb@48200000 {
        /delete-property/ phy;
        /delete-property/ phy-names;
    };
};
```

### 2. dwc3-ensemble.c driver fix
Changed `devm_clk_get()` to `devm_clk_get_optional()` with NULL checks so the driver probes even without clocks in the DTB.

### 3. Bootargs fixes (appkit-e7.dts)
- Added `clk_ignore_unused` — without this, `clk_disable_unused()` hangs (likely MHU→SE deadlock when trying to gate unused clocks)
- Uses `init=/sbin/preinit` — preinit sets up overlayfs writable root over cramfs, then exec's /sbin/init

### 4. Memory layout (appkit-e7.dts, from prior work)
- SRAM limited to 4MB (SRAM0 only) — SRAM1 is firewall-protected (FC5)
- HyperRAM 32MB (E7 has ISSI, not 64MB like E8)
- Hard-coded via `&mem_stitch` override to bypass DCT macros

## Verification

- [x] `adbd` present at `/usr/bin/adbd` in rootfs
- [x] Gadget script creates ADB + ECM composite device
- [x] `/dev/cu.usbmodem*` appears on Mac (`/dev/cu.usbmodem0012193076991`)
- [x] `adb devices` lists device (`eai-alif-e7-001  device`)
- [x] `adb shell` provides interactive root shell
- [x] Linux boots correctly from OSPI with Yocto DTB

## Remaining Validation

- [x] Clean Yocto rebuild produces bootable artifacts (no fdtput patching)
- [x] Verify `init=/sbin/preinit` is consistent between rootfs and bootargs — preinit sets up overlay, chroots to /sbin/init
- [x] Full pipeline: Yocto rebuild → stage → gen_toc → USB-OSPI flash → boot → overlay → ADB works
- [ ] Verify DCT tool doesn't interfere with hard-coded memory layout (deferred — not blocking)

## Implementation Notes

- DWC3 driver uses dummy regulators (vdd33/vdd18 not in DTB) — works fine since TF-A handles power
- USB gadget composite: ADB (FunctionFS) + CDC-ECM (network)
- Device IP: 192.168.55.2, host should be 192.168.55.1
- `clk_ignore_unused` is a workaround — long-term fix is to get MHU→SE→clock chain working

### 5. Overlayfs writable root (preinit + kernel config)
- `preinit` script creates tmpfs-backed overlayfs over read-only cramfs
- Uses `chroot` (not `switch_root` — BusyBox switch_root has argument parsing issue, looks for `/init` instead of `/sbin/init`)
- Kernel config: `CONFIG_OVERLAY_FS=y` via `overlayfs.cfg` fragment

## Files Modified

| File | Change |
|------|--------|
| `linux_alif/.../appkit/appkit-e7.dts` | DWC3 `/delete-property/`, bootargs fixes, memory layout |
| `linux_alif/drivers/usb/dwc3/dwc3-ensemble.c` | `devm_clk_get()` → `devm_clk_get_optional()` |
| `meta-eai/.../overlayfs-dev/files/preinit` | Overlayfs setup with chroot (not switch_root) |
| `meta-eai/.../linux/linux-alif_%.bbappend` | Added overlayfs.cfg, DWC3 patch, DTS patch |
| `meta-eai/.../linux/files/0001-arm-dts-*.patch` | AppKit-E7 DTS with all fixes |
| `meta-eai/.../linux/files/0002-usb-dwc3-*.patch` | DWC3 devm_clk_get_optional fix |
