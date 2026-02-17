# STM32MP1 Dual-Core Support

Status: In-Progress
Created: 2026-02-16

## Problem
The workspace supports nRF (BLE) and ESP32 (WiFi+BLE) targets but has no support for dual-core Linux+RTOS platforms. The STM32MP157D-DK1 has a Cortex-A7 (Linux) + Cortex-M4 (Zephyr) architecture that enables shared libraries between cores.

## Approach
Three parallel tracks (Tracks 2 and 3 deprioritized by user):
- **Track 1** — M4/Zephyr: Generic OpenOCD MCP server for M4 debugging — **COMPLETE**
- **Track 2** — A7/Linux: Docker-wrapped Linux build MCP server — **DEPRIORITIZED** (scaffold exists)
- **Track 3** — Integration: eai_ipc library + shared libs across cores — **SKIPPED**

## Solution

### Track 1: OpenOCD MCP Server — `claude-mcps/openocd-debug/`
Complete Rust MCP server using rmcp 0.3.2 with 10 tools:
- **Session**: `connect(cfg_file)` → session_id, `disconnect(session_id)`
- **Control**: `get_status`, `halt`, `run`, `reset(halt_after_reset)`
- **Firmware**: `load_firmware(file_path, address?)` — ELF/HEX/BIN via `load_image`
- **Memory**: `read_memory(address, count)`, `write_memory(address, value)`
- **Console**: `monitor(port, baud_rate, duration_seconds)` — UART capture via tokio-serial

Key design: TCL socket protocol (port 6666, 0x1a terminator), auto port allocation for multi-session, OpenOCD process lifecycle management.

### Track 2: Linux Build MCP — `claude-mcps/linux-build/` (deprioritized)
Scaffold exists with 9 tools wrapping Docker CLI. Compiles, 5 tests pass. Not actively maintained.

## Implementation Notes

### Files created
- `claude-mcps/openocd-debug/` — Full MCP server (Cargo.toml, src/{main,lib,config,openocd_client}.rs, src/tools/{mod,types,openocd_tools}.rs)
- `claude-mcps/linux-build/` — Scaffold only (same structure)
- `plans/stm32mp1-dual-core.md` — This plan

### Test results
- openocd-debug: 16 tests passing (TCL client parsing, config, args)
- linux-build: 5 tests passing (config, args, container state)

### Remaining work (for another session)
- Board profile: `knowledge/boards/stm32mp157d_dk1.yml`
- Knowledge items: STM32MP1 gotchas (RAM-only flash, OpenOCD cfg, remoteproc)
- CLAUDE.md: Add openocd-debug to MCP sections, common boards table
- zephyr-build: Add `stm32mp157c_dk2` to COMMON_BOARDS
- README.md + CLAUDE.md for openocd-debug

## Modifications
- Tracks 2 and 3 deprioritized by user — focus on Track 1 (OpenOCD MCP) only
- linux-build scaffold was already built before deprioritization; left in place
