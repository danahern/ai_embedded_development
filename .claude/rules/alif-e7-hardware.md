---
paths: ["**/alif-e7/**", "**/alif_e7*", "**/appkit-e7*", "**/linux-boot-e7*", "claude-mcps/alif-flash/**"]
---

# Alif E7 AppKit Hardware Interaction Rules

## Serial Port Setup (CRITICAL — do not guess)

| Port pattern | Device | Use | Baud |
|---|---|---|---|
| `/dev/cu.usbserial-*` | External FTDI adapter | SE-UART ISP flash protocol | 57600 |
| `/dev/cu.usbmodem*` | Onboard JLink VCOM | Linux console + TF-A boot output | 115200 |

## JLink VCOM Requires Active Session (CRITICAL)

The onboard JLink VCOM port (`usbmodem*`) **only produces output during an active JLink debug session**. Without it, the port is completely silent.

**To enable VCOM, run JLinkExe in background with a long sleep:**

```bash
# Create command file:
cat > /tmp/jlink_persist.jlink << 'EOF'
si SWD
speed 4000
device AE722F80F55D5_M55_HP
connect
sleep 300000
exit
EOF

# Run in background (must use -nogui 1):
/Applications/SEGGER/JLink/JLinkExe -nogui 1 -if SWD -speed 4000 \
  -device AE722F80F55D5_M55_HP -SelectEmuBySN 001219307699 \
  -AutoConnect 1 -CommandFile /tmp/jlink_persist.jlink &
```

**Sequence matters:** Power cycle board FIRST, wait 5+ seconds for boot, THEN start JLink session. Starting JLink before SE boot completes can interfere.

## Probe Serial Numbers

- **Onboard JLink** (VCOM + debug): Serial `001219307699`
- **J-Trace PRO** (external): Serial `001223000022`

## Flashing — When to Use Which Tool (CRITICAL)

**`jlink_flash` (fast, ~44 KB/s, ~78s for full image set):**
- Use for ALL image updates (TF-A, DTB, kernel, rootfs) at existing MRAM addresses
- Uses `loadbin` on M55_HP AP — MRAM is directly memory-mapped and writable
- Custom JLinkScript skips resets (SE manages boot sequence)
- Must power cycle after to trigger SE boot

**SE-UART `flash()` (slow, ~5 KB/s, ~15 min):**
- ONLY use when ATOC itself must change (new components, different addresses, initial setup)
- Writes AppTocPackage.bin + all images via ISP protocol
- Also requires power cycle after

**NEVER use SE-UART for routine image updates. It is 9x slower than jlink_flash.**

- **OSPI NOR Flash** (0xC0000000+): SETOOLS do NOT support OSPI programming. SE-UART `CMD_BURN_MRAM` rejects OSPI addresses. Use J-Link with FLM flash algorithm (`Ensemble_IS25WX256.FLM`).

## ATOC / gen_toc

- `gen_toc` only validates MRAM address range. OSPI addresses cause "Images DO NOT FIT" error.
- Valid address ranges: SRAM (0x50000000-0x63200000) and MRAM (0x80000000, 6MB).

## Power Cycle Protocol

After SE-UART flash: must **unplug/replug PRG_USB** for SE boot sequence. JLink reset alone is insufficient.

## SE-UART ISP Window

The SE accepts ISP commands for ~2-3 seconds after power-on. **Do NOT open the SE-UART port at 57600 during boot** or you will catch the SE in ISP mode and prevent normal boot.
