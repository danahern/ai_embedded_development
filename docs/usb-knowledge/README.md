# Alif E7 USB Knowledge Base

Reference documentation for bringing up USB on Linux for the Alif Ensemble E7. Covers the full stack from PHY hardware through gadget framework.

## Documents

| # | Topic | What's Covered |
|---|-------|----------------|
| [01](01-hardware.md) | Hardware | DWC3 controller specs, register map, USB PHY, clocks, power domains, DMA constraints |
| [02](02-secure-enclave.md) | Secure Enclave | AIPM run profiles, USB power/clock gating, MHU protocol, SE service IDs |
| [03](03-boot-sequence.md) | Boot Sequence | TF-A PHY init, Linux/Zephyr/bare-metal boot paths, pre-Linux requirements |
| [04](04-device-tree.md) | Device Tree | DT bindings (Linux + Zephyr), wrapper/child nodes, properties, known DT bugs |
| [05](05-kernel-drivers.md) | Kernel Drivers | dwc3-ensemble glue, DWC3 core, Zephyr UDC driver, Kconfig fragments |
| [06](06-gadget-configfs.md) | Gadget / ConfigFS | Current g_serial setup, ConfigFS howto, ADB/ECM requirements, host mode |
| [07](07-troubleshooting.md) | Troubleshooting | Known issues (14 documented), debug techniques, register dump guide, Yocto gotchas |

## Quick Reference

- **Base address**: `0x48200000` (DWC3 controller)
- **Controller ID**: `0x5533330B` (DWC3 release 3.30b)
- **USB mode**: 2.0 High-Speed (480 Mbps) only
- **PHY**: On-chip UTMI+ (no external PHY)
- **Interrupt**: GIC SPI 26 (Linux) / NVIC IRQ 101 (Zephyr)
- **Power domain**: PD_SYST (PD6)
- **Default gadget**: g_serial → /dev/ttyGS0 (target), /dev/ttyACM0 (host)
- **VID/PID**: 0x0525/0xa4a7 (Linux Foundation defaults)

## Critical Gotchas

1. **Three-level power control** — AIPM profile + VBAT registers + PHY POR must all be correct
2. **Power bits are inverted** — CLEAR to enable, SET to disable
3. **SE AIPM service IDs** — GET_RUN=310, SET_RUN=311 (some local headers have off-by-one bug)
4. **g_serial auto-binds UDC** — must force-disable via sed to use ConfigFS
5. **dr_mode hardcoded** to "peripheral" — host mode needs DT overlay
6. **Regulator supplies missing** from DT — driver expects vdd33/vdd18 but they're not wired
7. **DMA buffers must be in bulk SRAM** — not TCM (Zephyr/bare-metal)
8. **No ADB/ConfigFS** in official Yocto layers — only g_serial
9. **J1 is device port, J2/PRG_USB is FTDI only** — need separate cable for gadget
10. **4MB SRAM may OOM** with full USB stack — use OSPI HyperRAM for production

## How to Use

- Each document is self-contained — start with the topic you need
- **Sources**: Every fact traces back to [sources.md](sources.md) with source tags like [S01]
- **Open Questions**: Each doc lists remaining unknowns
- Cross-reference between docs via topic mentions

## Sources

13 sources ingested (Git repos + PDFs + conversation history). See [sources.md](sources.md) for full bibliography.
