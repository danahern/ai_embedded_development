---
paths: ["claude-mcps/alif-flash/**", "**/alif*/**", "**/linux-boot-e*"]
---

# Alif Ensemble Common Rules

## SE-UART ISP Protocol

Packet format: `[length, cmd, data..., checksum]`. All bytes including checksum sum to 0 mod 256. Data transfers use 240-byte chunks with 2-byte LE sequence numbers.

| Port pattern | Device | Use | Baud |
|---|---|---|---|
| `/dev/cu.usbserial-A10LOVM2` | FTDI adapter | SE-UART ISP flash protocol | 57600 |
| `/dev/cu.usbserial-AO009AHE` | FTDI adapter | UART2 (A32/Linux console) | 115200 |
| `/dev/cu.usbmodem*` | Onboard JLink VCOM | Debug output (requires active JLink session) | 115200 |

## Verified Flash Workflow (2026-03-07)

1. `app-gen-toc -f config.json` — generates AppTocPackage.bin
2. Write ATOC to MRAM via **JLink w4 commands** (ISP writes to ATOC area are silently dropped after full erase)
3. Write TFA/DTB via ISP (`flash()`) or JLink (`loadbin` — copy `.dtb` to `.bin` first)
4. Reset via JLink NSRST (`RSetType 2` + `r`)

**NEVER ask for manual power cycles.** Use JLink NSRST or ISP RESET_DEVICE instead. All reset types process ATOC identically.

**ATOC is one-shot:** The SE reads ATOC, processes it (boots configured cores), then clears the ATOC area. This is by design. After a successful boot, ATOC reads as zeros — this is normal, not a bug.

**ATOC persists across JLink sessions:** JLink's MRAM flash algorithm preserves w4 writes on disconnect. You can write ATOC in session 1 and reset in session 2. The "Flash download: Bank 0" message on disconnect writes back current MRAM state (including your writes), not a cached snapshot.

**ISP ATOC Write Bug:** After full MRAM erase, ISP BURN_MRAM silently drops writes to ATOC area (~0x8057xxxx). SE ACKs all commands but data is zeros. Both native tool and MCP fail. JLink writes to same addresses work. Workaround: JLink ATOC bootstrap.

**JLink DTB Format Rejection:** `loadbin` rejects `.dtb` files ("File is of unknown / unsupported format") due to DTB magic 0xD00DFEED. Workaround: `cp foo.dtb /tmp/dtb_raw.bin` then `loadbin /tmp/dtb_raw.bin 0x80200000`.

## USB-to-OSPI Flash Workflow

1. `gen_toc` + JLink ATOC w4 + NSRST with flasher config (`linux-boot-e7-ospi-usbflash.json`)
2. Connect SOC USB — flasher CDC-ACM appears at `/dev/cu.usbmodem12001`
3. XMODEM send combined OSPI image (~12MB, ~4.4 min at 46.3 KB/s)
4. **Hard maintenance erase** via native Alif tool (flasher hangs SE — no automated recovery)
5. `gen_toc` + JLink ATOC w4 + NSRST with boot config (TFA+DTB)
6. Linux boots from OSPI

## ATOC Failure Modes (from AUGD0005)

- **Part number mismatch**: If ATOC part number doesn't match SoC, ATOC is silently skipped (no boot, no error on A32 console)
- **Image verification failure**: If any non-bootable image fails verification, ALL APP core booting is skipped
- **"No ATOC" message**: Normal SE output when no valid ATOC found at expected MRAM location

## Validated Flash Facts (from systematic testing)

- **mramAddress minimum**: 0x80200000 for non-TFA entries (SE REV_B4 rejects lower). TFA at 0x80002000 is the exception.
- **All reset types process ATOC**: JLink NSRST, reset button, ISP RESET_DEVICE, cold power cycle — all trigger full SE reboot.
- **ISP user image writes work**: TFA, DTB at valid addresses persist via ISP.
- **ISP ATOC writes fail silently**: After full erase, use JLink for ATOC.
- **JLink access without ATOC**: Connect to M55_HE (`AE722F80F55D5_HE`).

See `plans/alif-flash-reset.md` for full test details.

## Multi-Device Support

Use `device` parameter on alif-flash MCP tools to target different boards:
- `device="alif-e7"` (default) — E7 AppKit/DevKit
- `device="alif-e8"` — E8 DevKit
