# RTT-Based OSPI Flash Programmer for Alif E7

**Status**: Blocked

## Summary

Custom M55_HP bare-metal firmware + Python host module for OSPI NOR flash programming via SEGGER RTT. Intended to replace FLM-based JLink OSPI programming (~7 KB/s) with direct OSPI controller access (~500 KB/s expected).

**BLOCKED:** M55_HP CPU cannot access the OSPI controller — BusFault (EXPMST bridge issue). The ~500 KB/s speed was never validated. On hardware, the tool hangs indefinitely. See knowledge item k-c3cbe077.

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
| Hardware validation | **BLOCKED** | M55_HP BusFault on OSPI access |

## Blocked On

M55_HP CPU access to OSPI controller (0x83002000) causes IMPRECISERR BusFault.
Root cause: EXPMST0 bus bridge not configured to forward M55_HP accesses to 0x8xxx_xxxx.
Need to investigate EXPMST0 configuration registers or find alternative approach.

## Key Decisions

- **cortex-m33 target**: Zephyr SDK 0.17.4 GCC doesn't support cortex-m55. M33 ISA is compatible.
- **Minimal libc stubs**: Provided memset/memcpy/strlen to avoid linking full libc.
- **Bitwise CRC32**: Avoided table to keep binary small (~5KB total).
- **pylink-square dependency**: Added to pyproject.toml for JLink SDK access.
