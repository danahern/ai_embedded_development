# Plan: Proper DTS Source Files and Yocto Machine Config

**Status:** In-Progress

## Problem Statement

We've been decompiling a binary DTB, hand-patching it with dtc, and recompiling. This doesn't scale to multiple boards (AppKit-E7, E8 coming soon) and risks breaking one variant when fixing another. Need proper DTS source files built by Yocto.

## Current State

- [x] `appkit-e7.dts` created in `linux_alif` and as Yocto patch
- [x] `appkit-e7.conf` machine config created in `meta-eai/conf/machine/`
- [x] `local.conf` updated to `MACHINE = "appkit-e7"`
- [x] MHU compatible strings already correct in upstream `ensemble-ex.dtsi` (no fix needed)
- [x] Yocto build kicked off (build ID: b5820228)
- [ ] Build completes successfully
- [ ] Flash and verify on hardware

## Architecture

```
linux_alif/arch/arm/boot/dts/alif/ensemble/
  common/ensemble-ex.dtsi          ← SoC-level (all boards)
  common/devkit_ex_dct_defines.h   ← peripheral enable/disable macros
  appkit/appkit-e7.dts             ← NEW: our board
  appkit/appkit-e8.dts             ← existing
  devkit/devkit-e8.dts             ← existing

meta-eai/conf/machine/
  appkit-e7.conf                   ← NEW: Yocto machine config
```

## Key Differences: E7 vs E8

| Feature | AppKit-E7 (ours) | AppKit-E8 |
|---------|-------------------|-----------|
| HyperRAM | 32MB (ISSI) | 64MB (Macronix) |
| HyperRAM enable | ISSI_HYPERRAM_EN=1 | AP_HYPERRAM_EN=1 |
| OSPI flash | ISSI (IS25WX256) | Macronix |
| Flash enable | ISSI_FLASH_EN=1 | MX_FLASH_EN=1 |
| DTB MRAM addr | 0x80200000 | 0x80010000 (?) |
| Model | appkit-e7 | appkit-e8 |
| Defconfig | appkit_e8_defconfig (identical) | appkit_e8_defconfig |

## Implementation Steps

### Step 1: Create appkit-e7.dts in kernel source
- Copy from appkit-e8.dts
- Change model to "appkit-e7"
- Override `mem_hyperam` to 32MB: `reg = <0xa0000000 0x2000000>`
- Fix bootargs: `earlycon=uart8250,mmio32,0x4901a000` (no baud rate), add `init=/sbin/preinit`
- Add UART2 `clock-frequency = <100000000>` workaround (remove clocks/pinctrl)
- File: `linux_alif/arch/arm/boot/dts/alif/ensemble/appkit/appkit-e7.dts`

### Step 2: Fix MHU compatible strings in ensemble-ex.dtsi
- **NOT NEEDED** — upstream `ensemble-ex.dtsi` already has correct split TX/RX nodes
- The binary DTB we'd been patching was from an older/different DTS
- Building from source DTS gets correct MHU nodes automatically

### Step 3: Create appkit-e7.conf Yocto machine config
- Based on appkit-e8.conf
- Set KERNEL_DEVICETREE to `alif/ensemble/appkit/appkit-e7.dtb`
- Fix DTB address: KERNEL_DTB_ADDR = 0x80200000
- Set ISSI_HYPERRAM_EN=1, AP_HYPERRAM_EN=0
- Set ISSI_FLASH_EN=1, MX_FLASH_EN=0
- Use ENABLE_PIE=1 (required for E7)
- File: `meta-eai/conf/machine/appkit-e7.conf`

### Step 4: Update local.conf to use new machine
- Change MACHINE = "appkit-e7" in container's local.conf

### Step 5: Build and test
- `bitbake alif-tiny-image` (or equivalent)
- Verify DTB is correct (dtc decompile, check HyperRAM, MHU, UART2)
- Flash DTB + rootfs (rootfs has /sbin/preinit for overlayfs)
- Verify boot, UART console, overlayfs

## Verification

- [ ] `appkit-e7.dtb` built by Yocto matches our verified working configuration
- [ ] HyperRAM shows as 32MB in kernel boot log
- [ ] earlycon works (no baud rate in earlycon string)
- [ ] ttyS0 registers and console works
- [ ] MHU driver doesn't print "Invalid compatible property"
- [ ] overlayfs writable root works (if preinit + switch_root included)
- [ ] Board boots and reaches shell prompt
- [ ] E8 DTB still builds correctly (no regression)

## Implementation Notes

- DTS added via Yocto patch (`0001-arm-dts-alif-add-appkit-e7-board-support.patch`) since kernel is git-fetched
- Patch adds both `appkit-e7.dts` and Makefile entry
- `ospi-config.inc` auto-detects flash type from machine name prefix (appkit=Macronix, devkit=ISSI)
  — E7 is an appkit with ISSI flash, so machine config uses strong `=` overrides AFTER the include
- `ISSI_HYPERRAM_EN` set unconditionally to "1" — E7 always needs 32MB HyperRAM as main memory
- `ALIF_TRUSTED_SRAM_BASE = 0x02300000` — SEROM v1.100.0 doesn't support SRAM1 remap
- Uses `appkit_e8_defconfig` — no E7-specific defconfig needed

## Risks

- UART2 clock-frequency workaround is E7-specific but goes in board DTS (OK)
- If kernel defconfig needs E7-specific options, may need appkit_e7_defconfig
