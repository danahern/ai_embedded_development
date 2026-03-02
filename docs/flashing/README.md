# Alif Ensemble Flashing & Debugging Reference

Comprehensive reference for flashing and debugging the Alif Ensemble E7/E8 SoC family. Covers all cores (Cortex-A32, M55_HP, M55_HE), all memory targets (MRAM, OSPI NOR), and all flash methods.

## Documents

| Document | Contents |
|----------|----------|
| [Boot Chain](boot-chain.md) | Power-on sequence, SE/SEROM/SERAM boot flow, ATOC processing, core startup order |
| [Memory Architecture](memory-architecture.md) | MRAM vs OSPI comparison, address maps, characteristics, programming models |
| [Flash Methods](flash-methods.md) | All flash paths: SE-UART ISP, J-Link, UART OSPI tool, TF-A program-from-MRAM, decision matrix |
| [ATOC Reference](atoc-reference.md) | ATOC JSON format, gen_toc process, image placement, config file inventory |
| [J-Link Debug](jlink-debug.md) | Per-core debug setup (A32, M55_HP, M55_HE), Ozone config, JLinkScript, AP mapping |
| [OSPI Controller](ospi-controller.md) | DWC SSI registers, ISSI IS25WX256 commands, XIP mode, driver API, programming sequences |
| [OSPI Flash Tool](ospi-flash-tool.md) | UART-based OSPI programming protocol, burner firmware, baud negotiation, file transfer |
| [E7 vs E8 Differences](e7-vs-e8.md) | OSPI IP changes, memory map shifts, clock differences, flashing implications |

## Quick Reference: Which Method to Use

| Scenario | Method | Persistent? | Speed |
|----------|--------|-------------|-------|
| Update boot images (kernel, DTB, TFA, rootfs) | SE-UART ISP (`gen_toc` + `flash`) | Yes | ~5 KB/s |
| Initial ATOC setup | SE-UART ISP (`maintenance` + `gen_toc` + `flash`) | Yes | ~5 KB/s |
| Temporary MRAM debug write | J-Link `loadbin` | No (SE overwrites on reboot) | ~44 KB/s |
| OSPI via J-Link FLM | J-Link `loadbin` at 0xC0xxxxxx | No (SE overwrites on reboot) | ~7 KB/s |
| OSPI via burner firmware | UART flash tool | Yes (if ATOC matches) | ~10-30 KB/s |
| OSPI via TF-A boot-time | Stage in MRAM + magic header | Yes | Native OSPI speed |

## Source Documents

- `AUGD0005` — Alif Security Toolkit User Guide v1.109.0
- `AAPN0001` — Segger Ozone and J-Link Debug v1.01
- `Alif_E7_HWRM_v2.9` — Hardware Reference Manual
- `Alif_E7_Datasheet_v2.12` — Datasheet
- `Alif_Ensemble_SWRM_v1.8` — Software Reference Manual
- `AUG00022` — Linux APSS v2.1.0
- `AUGD00013` — Getting Started with Linux Prebuilt Images
- `SPI_Flashing_Tool_User_guide_v1.2` — OSPI Flash Tool Protocol
- `AAPN0037` — E4/E6/E8 Differences from E1/E3/E5/E7
- `AlifSemiconductor.Ensemble.2.1.0` — Ensemble CMSIS SDK
