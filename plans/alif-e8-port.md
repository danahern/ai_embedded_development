# Alif E8 AppKit Port

**Status:** In-Progress
**Created:** 2026-03-09

## Goal

Port everything working on Alif E7 AppKit to E8 AppKit: Linux boot, ADB over USB, UART console, USB-to-OSPI flashing.

## Key E8 Differences from E7

- **SRAM1 at 0x02400000** (not 0x08000000) — AAPN0037
- **64MB Macronix HyperRAM** (not 32MB ISSI)
- **No separate Linux UART** — E8 AppKit has FT232R for SE-UART only
- **UART4** for console (not UART2)

## MRAM Layout (E8)

| Component | Address | Size |
|-----------|---------|------|
| ATOC header | 0x80000000 | 8KB |
| TF-A (bl32-e8.bin) | 0x80002000 | ~26KB |
| DTB | 0x80010000 | ~32KB |
| Kernel (xipImage) | 0x80020000 | ~4MB |
| RootFS (cramfs) | 0x80400000 | ~1.5MB |
| System MRAM | 0x80580000 | — |

## Checklist

- [x] TF-A builds and boots on E8 (ARM_TRUSTED_SRAM_BASE=0x02400000)
- [x] Linux kernel boots (system_state=SYSTEM_RUNNING, oops_count=0)
- [x] JLink device definitions for E8 (Devices.xml)
- [x] alif-flash MCP devices.py updated for E8 (M55_HE for MRAM access)
- [x] E8 DTS patch created (0003-arm-dts-alif-appkit-e8-mram-boot-workarounds.patch)
- [x] meta-eai appkit-e8.conf machine config created
- [x] Yocto build kicked off with USB support + ADB
- [x] Rootfs size analysis: core-image-minimal cramfs-xip = 4.2MB (libcrypto.so.3 = 3MB!)
- [x] adbd OpenSSL removal: stub auth, remove -lcrypto (bbappend + stub file)
- [x] MTD physmap config fragment for E8 (0x80400000, 0x180000)
- [x] E8 flash config JSON created (linux-boot-e8-mram.json, rootfs@0x80400000)
- [x] Verify no-OpenSSL adbd builds successfully (readelf: only libbsd.so.0, libc.so)
- [x] Verify rootfs fits in MRAM (1,425,408 bytes = 1.36MB, fits at 0x80400000 with 144KB margin)
- [x] Kernel rebuild with MTD physmap config fragment (MTD_PHYSMAP_START=0x80400000)
- [x] Flash all MRAM images (ISP, 17.5 min, build 3b216b34)
- [x] SE boot verified: ATOC processed, TFA booted on A32_0
- [x] Connect USB-C cable to MCU Device port (separate from Debug USB-C)
- [x] Verify ADB over USB (`adb devices` shows device) — verified 2026-03-10
- [x] cramfs-xip rootfs mount working (physmap-core.c fix for map_ram power-of-2 rounding)
- [x] Fix earlycon address in DTS patch (0x4901c000 for UART4, not 0x4901e000)
- [x] USB-to-OSPI flash prep: build-tfa.sh --usb-init, E8 OSPI usbflash config
- [ ] Test USB-to-OSPI flasher on E8 (needs MCU Device USB-C cable)
- [x] Enable HyperRAM in DTB — verified 2026-03-10: kernel boots, 64MB HyperRAM readable via JLink M55_HE
- [ ] HyperRAM causes init SIGSEGV — kernel boots with 71MB but busybox init crashes (exit 0x0b = signal 11). SRAM-only works. Needs investigation.
- [x] physmap-core.c fix propagated to Yocto build (already in linux_alif git, kernel_rebuild picks it up)
- [x] ADB working on E8 with SRAM-only + physmap fix — `eai-alif-e8-001` (verified 2026-03-10)
- [x] usb-ecm.sh E8 board detection working (grep /proc/device-tree/model for "e8")
- [x] ISP robust retry script for large MRAM writes (SE pauses every ~234KB, needs 5s timeout + retries)
- [x] Knowledge system updated with E8 findings (5 items captured, rules regenerated)

## Build Artifacts

- **meta-eai host path**: `/Users/danahern/code/claude/work/firmware/linux/yocto/meta-eai/`
- **Yocto MACHINE**: `appkit-e8` (in local.conf)
- **Yocto build ID**: `2fc41c69` (no-OpenSSL adbd rebuild)
- **TF-A**: Hand-built `bl32-e8.bin` in `tools/setools/build/images/`
- **app-device-config**: `app-device-config-e8.json` in `tools/setools/build/config/`

## Key Discoveries

- **libcrypto.so.3 = 3MB** — dominates rootfs, adbd only uses RSA_verify which can be stubbed
- **Kernel MTD_PHYSMAP_START override doesn't propagate** — Yocto DCT tool or defconfig ignores machine config. Fixed with explicit .cfg fragment.
- **UART4 address = 0x4901c000** (not 0x4901e000 as in initial DTS patch — cosmetic bug, earlycon output goes nowhere on E8 anyway)
- **E8 TF-A is 26KB** (E7 is 30KB — FLASH_EN=0 accounts for size difference, ENABLE_STACK_PROTECTOR=strong IS included)
- **E8 DevKit has 3 USB connectors**: Debug USB-C (SE-UART + JTAG), MCU Device USB-C (DWC3 gadget), USB-A (host)
- **ADB requires MCU Device USB-C cable** — separate from Debug USB-C. No ADB without this cable.
- **Pin mux errors on port 15** during SE boot — OSPI pins, non-fatal for MRAM-only boot
- **SE-UART only** — single FT232R (BG03TXVI), no second FTDI for Linux UART on E8

## Notes

- E8 AppKit has no separate Linux UART — console only via USB gadget (ADB shell)
- HyperRAM: TF-A has HYPRAM_EN=1 (Macronix init runs), but DTB has it disabled pending verification
- USB-to-OSPI: OSPI clock gate at 0x4902F03C IS enabled in device config (confirmed in SE boot log)
- USB-to-OSPI: existing flasher-hp.bin should work on E8 (same DWC3, OSPI direct register access)
- USB-to-OSPI config: `linux-boot-e8-ospi-usbflash.json` created, needs bl32-usbinit-e8.bin build
- ~7MB SRAM available (SRAM0 4MB + SRAM1 3MB - 128KB TF-A)
- ISP flash at 57600 baud (~5 KB/s) — ~17 min for full MRAM write
