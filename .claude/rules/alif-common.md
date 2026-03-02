---
paths: ["claude-mcps/alif-flash/**", "**/alif*/**", "**/linux-boot-e*"]
---

# Alif Ensemble Common Rules

## SE-UART ISP Protocol

Packet format: `[length, cmd, data..., checksum]`. All bytes including checksum sum to 0 mod 256. Data transfers use 240-byte chunks with 2-byte LE sequence numbers.

| Port pattern | Device | Use | Baud |
|---|---|---|---|
| `/dev/cu.usbserial-*` | External FTDI adapter | SE-UART ISP flash protocol | 57600 |
| `/dev/cu.usbmodem*` | Onboard JLink VCOM | Linux console + TF-A boot output | 115200 |

## Flashing Tool Selection (CRITICAL)

**NEVER use `jlink_flash` for persistent image updates.** The SE reprograms ALL ATOC-managed images (kernel, rootfs, DTB, bl32) from its internal storage on every power cycle. J-Link writes to OSPI and MRAM verify successfully but are silently overwritten before the A32 starts. This is the SE's normal security model, not a bug.

**SE-UART `flash()` — use for ALL persistent image updates:**
- Call `alif-flash.gen_toc(config=...)` then `alif-flash.flash(config=..., maintenance=true)`
- Writes to SE's internal storage; SE programs MRAM/OSPI from this copy on each boot
- ~5 KB/s for MRAM images directly; OSPI images use TF-A MRAM-staging programmer (~42 KB/s)
- Required when adding new ATOC entries or changing addresses

**`jlink_flash` — only for temporary debugging:**
- Useful for reading back memory, testing transient changes, or writing to non-ATOC regions
- Writes do NOT survive a power cycle for any ATOC-managed address
- Speed: ~44 KB/s MRAM, ~6 KB/s OSPI (but irrelevant — writes are overwritten)

**OSPI NOR Flash** (0xC0000000+): Use TF-A MRAM-staging programmer (see plan `alif-e7-ospi-boot/`).

## ATOC / gen_toc

- `gen_toc` only validates MRAM address range. OSPI addresses cause "Images DO NOT FIT" error.
- Valid address ranges: SRAM (0x50000000-0x63200000) and MRAM (0x80000000, 6MB).

## Power Cycle Protocol

After SE-UART flash: must **unplug/replug PRG_USB** for SE boot sequence. JLink reset alone is insufficient.

## SE-UART ISP Window

The SE accepts ISP commands for ~2-3 seconds after power-on. **Do NOT open the SE-UART port at 57600 during boot** or you will catch the SE in ISP mode and prevent normal boot.

## Multi-Device Support

Use `device` parameter on alif-flash MCP tools to target different boards:
- `device="alif-e7"` (default) — E7 AppKit/DevKit
- `device="alif-e8"` — E8 DevKit
