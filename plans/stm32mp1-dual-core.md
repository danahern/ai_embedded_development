# STM32MP1 Dual-Core Support

Status: In-Progress
Created: 2026-02-16

## Problem
The workspace supports nRF (BLE) and ESP32 (WiFi+BLE) targets but has no support for dual-core Linux+RTOS platforms. The STM32MP157D-DK1 has a Cortex-A7 (Linux) + Cortex-M4 (Zephyr) architecture that enables shared libraries between cores.

## Approach
Three parallel tracks:
- **Track 1** — M4/Zephyr: Generic OpenOCD MCP server for M4 debugging — **COMPLETE**
- **Track 2** — A7/Linux: Docker-wrapped Linux build MCP server — **COMPLETE**
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

### Track 2: Linux Build MCP — `claude-mcps/linux-build/`
Complete Rust MCP server using rmcp 0.3.2 with 9 tools:
- **Container lifecycle**: `start_container(name?, image?, workspace_dir?)`, `stop_container(container)`, `container_status(container)`
- **Build operations**: `run_command(container, command, workdir?)`, `build(container, command?, workdir?)`, `list_artifacts(container, container_path?)`
- **Deployment**: `collect_artifacts(container, container_path?, host_path)`, `deploy(file_path, remote_path?, board_ip?)`, `ssh_command(command, board_ip?)`

Key design: Docker CLI wrapper (no Docker API dependency), `sleep infinity` container pattern for iterative `docker exec`, host-side SCP/SSH for deployment.

## Implementation Notes

### Files created
- `claude-mcps/openocd-debug/` — Full MCP server (Cargo.toml, src/{main,lib,config,openocd_client}.rs, src/tools/{mod,types,openocd_tools}.rs)
- `claude-mcps/linux-build/` — Full MCP server (Cargo.toml, src/{main,lib,config,docker_client}.rs, src/tools/{mod,types,linux_build_tools}.rs, README.md, PRD.md, CLAUDE.md)
- `plans/stm32mp1-dual-core.md` — This plan

### Test results
- openocd-debug: 16 tests passing (TCL client parsing, config, args)
- linux-build: 13 tests passing (config, args, container state, handler construction, validation errors, server info)

### Remaining work (for another session)
- Board profile: `knowledge/boards/stm32mp157d_dk1.yml`
- Knowledge items: STM32MP1 gotchas (RAM-only flash, OpenOCD cfg, remoteproc)
- README.md + CLAUDE.md for openocd-debug
- Track 3 (eai_ipc library) if dual-core development proceeds

## Modifications
- Track 2 initially deprioritized, then completed in a separate session
- Track 3 skipped — will implement when dual-core hardware workflow is tested
- linux-build registered in `.mcp.json` and workspace CLAUDE.md updated with tool listings and workflow
