# Plan: Deploy USB-to-OSPI Flasher for Fast OSPI Programming

**Status:** Complete

## Context

Current OSPI programming via 3-pass SE-UART MRAM staging takes ~40+ minutes per cycle. The `alif_usb-to-ospi-flasher` project provides direct M55→OSPI flash programming over USB CDC-ACM + XMODEM at ~60 KB/s.

## Approach

Combined image (rootfs padded to 8MB + kernel), always reflashes both. Two ATOC configs: programming mode (TF-A USB-init + M55 flasher) and normal boot mode (TFA+DTB, OSPI XIP).

### SE Hang Fix (2026-03-08)

`SERVICES_set_run_cfg(USB_PHY_MASK)` from M55_HP hangs the SE. Fixed with split architecture:
- **A32/TF-A** (`bl32-usbinit.bin`): Calls `service_enable_usb_phy()` via SE AIPM to enable USB PHY power domain, then parks A32 in WFE loop (prevents BL33 jump to OSPI during programming)
- **M55_HP/Flasher**: Does direct register writes for USB clocks (CGU, PERIPH_CLK_ENA) and PHY (VBAT, CLKCTL) — no SE service calls

JLink diagnostic confirmed: all USB registers correct, DWC3 initialized in device mode, RunStop=1. **USB link state = Disconnected** because SoC USB is on J2 (separate from J1/PRG_USB). Need cable from J2 to Mac.

## Implementation

### Completed

- [x] Build flasher firmware (cbuild, DevKit-E7-HP, release) — 131KB binary
- [x] Create programming mode gen_toc config (`linux-boot-e7-ospi-usbflash.json`)
- [x] Create combined image build script (`make-ospi-image.sh`)
- [x] Create XMODEM transfer script (`xmodem-send.py` + `flash-ospi-usb.sh`)
- [x] Copy flasher binary to `images/flasher-hp.bin`
- [x] Update README.md with USB flasher documentation

### Hardware Verification (2026-03-07)

- [x] Flash programming mode ATOC via JLink ATOC bootstrap (ISP ATOC writes fail)
- [x] Power cycle, verify USB CDC-ACM enumerates — `/dev/cu.usbmodem12001` (VID 0x0525, PID 0xa4a7)
- [x] XMODEM transfer combined image — 12.1MB in 256s (46.3 KB/s)
- [x] Flash normal boot ATOC via JLink w4 + NSRST (same session required)
- [x] Linux boots from OSPI — cramfs rootfs (4932 KB) + XIP kernel
- [x] **Power-cycle persistence test** — OSPI data survives power cycle, Linux boots

### Issues Found

- **~~Flasher SE hang~~**: Fixed — TF-A on A32 handles AIPM USB PHY call instead of M55_HP. See "SE Hang Fix" above.
- **USB connector**: SoC USB is on J2 (Micro-B), separate from J1/PRG_USB. Need second cable.
- **~~JLink ATOC clearing~~**: Fixed — `jlink_flash` now writes AppTocPackage.bin alongside images (ATOC address = system_mram_base - atoc_size). No more stale ATOC issues.
- **Console missing**: `Warning: unable to open an initial console.` — rootfs needs `/dev/console` node.
- **Actual speed**: 46.9 KB/s (not 60 KB/s as estimated). Total ~7 min realistic with recovery overhead.

## Build Environment

- CMSIS Toolbox 2.12.0 (bundled in flasher project)
- ARM GNU Toolchain 14.2.Rel1 at `~/code/3rdparty/arm-gnu-toolchain/`
- CMSIS Packs at `~/code/3rdparty/cmsis-toolbox/cmsis-toolbox-darwin-arm64/packs/`
- ThreadX pack URL: `https://github.com/alifsemi/alif_ensemble-Azure-RTOS/releases/download/v2.0.0/AlifSemiconductor.ThreadX.2.0.0.pack`
- Build note: GCC 14 requires `-Wno-incompatible-pointer-types` in `cdefault.yml`

## Files Created

| File | Description |
|------|-------------|
| `setools/linux-boot-e7-ospi-usbflash.json` | Programming mode ATOC (TF-A USB-init + M55 flasher) |
| `images/bl32-usbinit.bin` | TF-A USB-init variant (AIPM + WFE halt, 30KB) |
| `make-ospi-image.sh` | Builds rootfs+kernel combined image |
| `flash-ospi-usb.sh` | Wrapper for XMODEM transfer |
| `xmodem-send.py` | XMODEM-1K sender over USB CDC-ACM |
| `images/flasher-hp.bin` | Built flasher firmware binary |
| `images/ospi-combined.bin` | Combined OSPI image (generated) |

## Time Estimates

| Operation | Duration |
|-----------|----------|
| JLink flash programming mode ATOC | ~2 sec |
| SE boot + USB enumerate | ~5 sec |
| XMODEM transfer (12MB @ 47 KB/s) | ~4.2 min |
| JLink flash normal boot ATOC | ~2 sec |
| Power cycle + boot | ~30 sec |
| **Total per flash cycle** | **~5 min** |
