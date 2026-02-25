# RTT-Based OSPI Flash Programmer for Alif E7

**Status**: In-Progress

## Summary

Custom M55_HP bare-metal firmware + Python host module for high-speed OSPI NOR flash programming via SEGGER RTT. Replaces FLM-based JLink OSPI programming (~7 KB/s) with direct OSPI controller access (~500 KB/s expected, 70x speedup).

## Components

| Component | Status | Location |
|-----------|--------|----------|
| Firmware (bare-metal M55_HP) | Done | `firmware/tools/ospi-programmer/` |
| OSPI driver port (from TF-A) | Done | `firmware/tools/ospi-programmer/src/ospi_drv.c` |
| Flash operations | Done | `firmware/tools/ospi-programmer/src/ospi_flash.c` |
| RTT protocol | Done | `firmware/tools/ospi-programmer/src/protocol.h` |
| Host Python module | Done | `claude-mcps/alif-flash/src/alif_flash/ospi_rtt.py` |
| MCP tool (ospi_program) | Done | `claude-mcps/alif-flash/src/alif_flash/server.py` |
| ATOC config | Done | `firmware/linux/alif-e7/setools/linux-boot-e7-ospi-rtt.json` |
| Host-side tests | Done (37 tests) | `claude-mcps/alif-flash/tests/test_ospi_rtt.py` |
| Hardware validation | Pending | Requires physical board |

## Remaining

- Build firmware and load via ATOC onto hardware
- Verify RTT communication via embedded-probe MCP
- Test OSPI flash init + READ_ID on hardware
- End-to-end: erase + program + verify cycle
- Performance benchmarking

## Key Decisions

- **cortex-m33 target**: Zephyr SDK 0.17.4 GCC doesn't support cortex-m55. M33 ISA is compatible.
- **Minimal libc stubs**: Provided memset/memcpy/strlen to avoid linking full libc.
- **Bitwise CRC32**: Avoided table to keep binary small (~5KB total).
- **pylink-square dependency**: Added to pyproject.toml for JLink SDK access.
