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

**`jlink_flash` (fast, ~44 KB/s MRAM):**
- Use for ALL image updates (TF-A, DTB, kernel, rootfs) at existing MRAM addresses
- Uses `loadbin` on M55_HP — MRAM is directly memory-mapped and writable
- Must power cycle after to trigger SE boot

**SE-UART `flash()` (slow, ~5 KB/s):**
- ONLY use when ATOC itself must change (new components, different addresses, initial setup)
- Writes AppTocPackage.bin + all images via ISP protocol

**NEVER use SE-UART for routine image updates. It is 9x slower than jlink_flash.**

**OSPI NOR Flash** (0xC0000000+): SE-UART does NOT support OSPI. Use J-Link with FLM flash algorithm.

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
