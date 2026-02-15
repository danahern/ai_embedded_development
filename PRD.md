# Product Requirements Document: AI-Assisted Embedded Development Workspace

## Overview

An integrated workspace that enables Claude Code to build, flash, debug, and analyze embedded firmware across multiple hardware platforms. Four custom MCP (Model Context Protocol) servers expose hardware tooling as AI-callable tools, allowing Claude to operate as a full-stack embedded development assistant.

**Core thesis**: Embedded development requires constant context-switching between build systems, debug probes, serial monitors, and logic analyzers. By exposing these as MCP tools, Claude can orchestrate the entire workflow — from building firmware to validating boot via RTT to analyzing signal integrity — without the developer leaving the conversation.

## Component PRDs

Each MCP server has its own PRD with full tool specifications, architecture details, and design decisions:

| Component | Location | Tools | Language |
|-----------|----------|-------|----------|
| [embedded-probe](claude-mcps/embedded-probe/PRD.md) | `claude-mcps/embedded-probe/` | 27 | Rust |
| [saleae-logic](claude-mcps/saleae-logic/PRD.md) | `claude-mcps/saleae-logic/` | 21 | Python |
| [esp-idf-build](claude-mcps/esp-idf-build/PRD.md) | `claude-mcps/esp-idf-build/` | 8 | Rust |
| [zephyr-build](claude-mcps/zephyr-build/PRD.md) | `claude-mcps/zephyr-build/` | 5 | Rust |
| **Total** | | **61** | |

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Claude Code (AI)                       │
│  Reads code, writes firmware, orchestrates hardware ops  │
└────────┬──────────┬──────────┬──────────┬───────────────┘
         │          │          │          │
    ┌────▼───┐ ┌───▼────┐ ┌──▼───┐ ┌───▼──────┐
    │zephyr- │ │esp-idf-│ │embed-│ │saleae-   │
    │build   │ │build   │ │ded-  │ │logic     │
    │(Rust)  │ │(Rust)  │ │probe │ │(Python)  │
    │5 tools │ │8 tools │ │(Rust)│ │21 tools  │
    └───┬────┘ └───┬────┘ │27   │ └────┬─────┘
        │          │      │tools│      │
        ▼          ▼      └──┬──┘      ▼
    ┌────────┐ ┌────────┐   │    ┌──────────┐
    │west CLI│ │idf.py  │   │    │Logic 2   │
    │        │ │        │   │    │(gRPC)    │
    └────────┘ └────────┘   │    └──────────┘
                            ▼
                    ┌──────────────┐
                    │  probe-rs    │
                    │  esptool     │
                    │  nrfjprog    │
                    └──────┬──────┘
                           ▼
                    ┌──────────────┐
                    │   Hardware   │
                    │  J-Link      │
                    │  ST-Link     │
                    │  DAPLink     │
                    │  USB Serial  │
                    └──────────────┘
```

### Communication Model

All four MCP servers communicate with Claude Code over stdio (stdin/stdout JSON-RPC). Three are compiled Rust binaries using the RMCP SDK; one is a Python process using the MCP Python SDK. Each server manages its own state and subprocess lifecycle.

| Server | Language | SDK | Transport to Hardware |
|--------|----------|-----|----------------------|
| zephyr-build | Rust | rmcp 0.3.2 | west CLI subprocess |
| esp-idf-build | Rust | rmcp 0.3.2 | idf.py CLI subprocess |
| embedded-probe | Rust | rmcp 0.3.2 | probe-rs library + vendor CLI subprocesses |
| saleae-logic | Python | mcp >=1.0.0 | logic2-automation gRPC to Logic 2 desktop app |

## MCP Server Summaries

### zephyr-build — Zephyr RTOS Build Server (5 tools)

Wraps the `west` build system so Claude can compile firmware for any supported board, manage build artifacts, and run long builds in the background.

**Tools**: `list_apps`, `list_boards`, `build`, `clean`, `build_status`

Key capabilities:
- Background builds with tokio::spawn (poll via `build_status`)
- Hardcoded common boards for instant lookup + `west boards` for full list
- Workspace auto-detection from `.west/` directory or CLI args

Full specification: [claude-mcps/zephyr-build/PRD.md](claude-mcps/zephyr-build/PRD.md)

---

### esp-idf-build — ESP-IDF Build/Flash/Monitor Server (8 tools)

Wraps `idf.py` for the full ESP32 development lifecycle across all 10 chip variants (ESP32, S2, S3, C2, C3, C5, C6, C61, H2, P4).

**Tools**: `list_projects`, `list_targets`, `set_target`, `build`, `flash`, `monitor`, `clean`, `build_status`

Key capabilities:
- Multi-segment flashing (bootloader + partition table + app in one call)
- Duration-based serial monitoring (capture boot logs, not interactive)
- IDF environment auto-discovery and caching

Full specification: [claude-mcps/esp-idf-build/PRD.md](claude-mcps/esp-idf-build/PRD.md)

---

### embedded-probe — Debug Probe & Flash Server (27 tools)

Connects to debug probes (J-Link, ST-Link, DAPLink), flashes firmware, sets breakpoints, reads/writes memory, and communicates via RTT. Supports ARM Cortex-M, RISC-V, and vendor-specific toolchains.

**Tools across 8 categories**:
- Probe management: `list_probes`, `connect`, `probe_info`
- Debug control: `halt`, `run`, `reset`, `step`
- Memory: `read_memory`, `write_memory`
- Breakpoints: `set_breakpoint`, `clear_breakpoint`
- Flash: `flash_erase`, `flash_program`, `flash_verify`
- RTT: `rtt_attach`, `rtt_detach`, `rtt_channels`, `rtt_read`, `rtt_write`, `run_firmware`
- Workflow: `get_status`, `validate_boot`, `disconnect`
- Vendor: `esptool_flash`, `esptool_monitor`, `nrfjprog_flash`, `load_custom_target`

Key capabilities:
- probe-rs as native Rust debug engine (no subprocess overhead for core operations)
- `validate_boot`: single call does flash + reset + RTT pattern match with timeout
- Vendor fallbacks for Xtensa ESP32 (esptool) and Nordic-specific features (nrfjprog)

Full specification: [claude-mcps/embedded-probe/PRD.md](claude-mcps/embedded-probe/PRD.md)

---

### saleae-logic — Logic Analyzer & Protocol Analysis Server (21 tools)

Captures digital and analog signals, decodes protocols (I2C, SPI, UART, CAN), performs statistical analysis with numpy/pandas, reads decoded bytes with ASCII translation, and generates custom protocol decoders.

**Tools across 5 categories**:
- Capture & device: `get_app_info`, `list_devices`, `start_capture`, `stop_capture`, `wait_capture`, `close_capture`, `save_capture`, `load_capture`
- Protocol analysis: `add_analyzer`, `add_high_level_analyzer`, `export_analyzer_data`, `export_raw_data`
- Intelligence: `analyze_capture`, `search_protocol_data`, `get_timing_info`, `read_protocol_data`, `deep_analyze`
- Advanced: `configure_trigger`, `compare_captures`, `stream_capture`, `create_extension`

Key capabilities:
- Smart sample rate auto-selection for digital+analog captures
- Deep statistical analysis: timing distributions (p95/p99), FFT spectrum, jitter, error rates
- Protocol byte extraction with ASCII translation (UART, I2C, SPI)
- Custom HLA extension generation from Python decode logic
- Regression testing via capture comparison

Full specification: [claude-mcps/saleae-logic/PRD.md](claude-mcps/saleae-logic/PRD.md)

## Workspace Structure

```
embedded-workspace/
├── .mcp.json                  # MCP server registration for Claude Code
├── CLAUDE.md                  # Workspace conventions and typical workflows
├── PRD.md                     # This document
├── setup.sh                   # Automated setup script
│
├── claude-config/             # Claude Code skills and configuration (submodule)
├── claude-mcps/               # MCP servers (submodule)
│   ├── embedded-probe/        #   Rust — 27 debug/flash tools
│   │   └── PRD.md
│   ├── zephyr-build/          #   Rust — 5 build tools
│   │   └── PRD.md
│   ├── esp-idf-build/         #   Rust — 8 build/flash/monitor tools
│   │   └── PRD.md
│   └── saleae-logic/          #   Python — 21 analysis tools
│       └── PRD.md
│
├── zephyr-apps/               # Zephyr applications + west manifest (submodule)
│   ├── apps/                  #   Application source code
│   └── west.yml               #   West manifest
│
├── esp-dev-kits/              # ESP-IDF example projects (cloned)
├── test-tools/                # Python testing utilities (submodule)
│
├── zephyr/                    # Zephyr RTOS source (west-managed, gitignored)
├── bootloader/                # MCUboot (west-managed, gitignored)
├── modules/                   # Zephyr HAL modules (west-managed, gitignored)
└── tools/                     # West tools (west-managed, gitignored)
```

**Git strategy**: The workspace repo tracks submodule references and configuration. West-managed dependencies (Zephyr, MCUboot, modules) are gitignored — they're fetched by `west update`. This keeps the repo small while ensuring reproducible builds via the west manifest.

## End-to-End Workflows

### Zephyr Firmware Development

```
1. Build
   zephyr-build.build(app="sensor_app", board="nrf52840dk/nrf52840", pristine=true)
   → artifact: apps/sensor_app/build/zephyr/zephyr.elf

2. Connect probe
   embedded-probe.connect(probe_selector="auto", target_chip="nRF52840_xxAA")
   → session_id

3. Flash + validate boot
   embedded-probe.validate_boot(session_id, file_path="...zephyr.elf",
       success_pattern="Booting Zephyr", timeout_ms=5000)
   → {success: true, boot_time_ms: 1234, rtt_output: "Booting Zephyr..."}

4. Monitor runtime
   embedded-probe.rtt_read(session_id)
   → Live RTT output from firmware
```

### ESP-IDF Development

```
1. Configure target
   esp-idf-build.set_target(project="my_project", target="esp32s3")

2. Build
   esp-idf-build.build(project="my_project")
   → Compiles bootloader + partition table + application

3. Flash (multi-segment, automatic)
   esp-idf-build.flash(project="my_project", port="/dev/cu.usbserial-1110")

4. Monitor serial output
   esp-idf-build.monitor(project="my_project", port="/dev/cu.usbserial-1110",
       duration_seconds=10)
   → Captured boot + runtime output
```

### Signal Analysis & Protocol Debugging

```
1. Capture I2C communication
   saleae-logic.start_capture(channels=[0,1], duration_seconds=2)
   saleae-logic.wait_capture(capture_id)

2. Decode protocol
   saleae-logic.add_analyzer(capture_id, "I2C", {"SCL": 0, "SDA": 1})

3. Quick summary
   saleae-logic.analyze_capture(capture_id, analyzer_index=0)
   → {packet_count: 42, error_count: 0, addresses: ["0x48", "0x68"]}

4. Statistical deep dive
   saleae-logic.deep_analyze(capture_id, analyzer_index=0)
   → {timing: {mean_us: 125, p99_us: 340}, throughput: "42 txn/s"}

5. Read raw bytes
   saleae-logic.read_protocol_data(capture_id, analyzer_index=0, ascii=true)
   → {bytes: ["0x48", "0x00", "0xFF"], ascii: "H.."}
```

### Cross-Tool: Build + Capture + Flash + Validate

```
1. Start signal capture (background)
   saleae-logic.start_capture(channels=[0,1,2,3], duration_seconds=10)

2. Flash new firmware
   embedded-probe.validate_boot(session_id, file_path, success_pattern="App ready")

3. Wait for capture
   saleae-logic.wait_capture(capture_id)

4. Analyze boot-time I2C traffic
   saleae-logic.add_analyzer(capture_id, "I2C", {"SCL": 2, "SDA": 3})
   saleae-logic.analyze_capture(capture_id, analyzer_index=0)

5. Verify signal integrity
   saleae-logic.deep_analyze(capture_id, channel=0)
   → Frequency, jitter, duty cycle of clock line
```

### Custom Protocol Decoder

```
1. Create HLA extension for proprietary protocol
   saleae-logic.create_extension(
       name="My Sensor Protocol",
       decode_body="if data.type == 'data': ...",
       result_types={"reading": "Sensor: {{data.value}}"}
   )

2. Attach to low-level analyzer
   saleae-logic.add_high_level_analyzer(capture_id,
       extension_directory=ext_dir, name="MySensorProtocol",
       input_analyzer_index=0)

3. Export decoded sensor readings
   saleae-logic.export_analyzer_data(capture_id, analyzer_index=1)
```

## Test Coverage

| Server | Tests | Hardware Needed | Run Command |
|--------|-------|-----------------|-------------|
| embedded-probe | 14 | No | `cd claude-mcps/embedded-probe && cargo test` |
| zephyr-build | 19 | No | `cd claude-mcps/zephyr-build && cargo test` |
| esp-idf-build | 16 | No | `cd claude-mcps/esp-idf-build && cargo test` |
| saleae-logic | 25 | No | `cd claude-mcps/saleae-logic && .venv/bin/python -m pytest tests/test_analysis.py tests/test_server_startup.py` |
| **Total** | **74** | | |

All 74 tests pass without any hardware connected.

## Prerequisites

| Requirement | For | Installation |
|-------------|-----|-------------|
| Rust 1.70+ | embedded-probe, zephyr-build, esp-idf-build | rustup |
| Python 3.10+ | saleae-logic, Zephyr tooling | System or pyenv |
| west | Zephyr builds | `pip install west` |
| Zephyr SDK | Zephyr compilation | [Getting Started Guide](https://docs.zephyrproject.org/latest/develop/getting_started/index.html) |
| ESP-IDF v5+ | ESP32 builds | [ESP-IDF Setup](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/) |
| Saleae Logic 2 | Signal analysis | [Saleae Download](https://www.saleae.com/downloads/) (enable automation in Preferences) |
| Debug probe | Flashing/debugging | J-Link, ST-Link, DAPLink, or CMSIS-DAP |

## Setup

```bash
# Clone with submodules
git clone --recursive <repo-url>
cd embedded-workspace

# Run automated setup
./setup.sh

# Or manually:

# 1. Initialize west workspace
cd zephyr-apps && west init -l . && west update && cd ..

# 2. Build Rust MCP servers
cd claude-mcps/embedded-probe && cargo build --release && cd ../..
cd claude-mcps/zephyr-build && cargo build --release && cd ../..
cd claude-mcps/esp-idf-build && cargo build --release && cd ../..

# 3. Set up Python MCP server
cd claude-mcps/saleae-logic
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
cd ../..

# 4. Verify MCP registration
cat .mcp.json  # Should list all 4 servers with absolute paths
```

## Design Principles

**1. Tools over instructions**: Instead of generating shell commands for the user to copy-paste, Claude calls tools directly. This eliminates transcription errors and enables multi-step automation.

**2. Subprocess isolation**: Build servers (zephyr-build, esp-idf-build) wrap their respective CLIs as subprocesses rather than linking libraries. This avoids version coupling and uses the same code paths developers would use manually.

**3. Lazy dependencies**: saleae-logic imports `logic2-automation` only on first tool use and `numpy`/`pandas` only when `deep_analyze` is called. This keeps startup fast and allows tool listing/registration without heavy dependencies.

**4. Absolute paths everywhere**: Logic 2 runs as a separate process with its own CWD. All user-supplied paths are resolved to absolute before sending over gRPC. This was a production bug — relative paths silently failed.

**5. Background builds**: Long builds (Zephyr/ESP-IDF can take 30-120 seconds) run in background with tokio::spawn. Claude can continue the conversation and poll `build_status` instead of blocking.

**6. Vendor fallbacks**: probe-rs handles most debug probes natively, but Xtensa ESP32 chips need esptool and some Nordic features need nrfjprog. The embedded-probe server provides both paths.

**7. Session-based state**: embedded-probe uses session IDs for debug connections. saleae-logic uses capture IDs and analyzer indices. State lives in the MCP server process, not on disk.

## Future Work

Captured during code review. Not committed — tracked here so they don't get lost.

### Multi-Project Scaling
- **App scaffolding script**: `scripts/new-app.sh <name> <board>` to generate CMakeLists.txt, prj.conf, board overlays, and test skeleton from a template
- **Register shared libs in west.yml as modules**: Eliminate per-app ZEPHYR_EXTRA_MODULES wiring — apps just set `CONFIG_CRASH_LOG=y` and it works
- **`build_all` tool in zephyr-build MCP**: Build every app in the workspace to catch regressions after library changes
- **Split LEARNINGS.md by topic**: `learnings/zephyr-build.md`, `learnings/nrf-chips.md`, `learnings/esp-idf.md` etc. — read selectively based on connected hardware

### Workspace Cleanup
- **Delete duplicate board overlays in crash_debug app**: `apps/crash_debug/boards/` duplicates `lib/crash_log/boards/` — let Zephyr auto-discover from the library
- **Move WiFi credentials to gitignored local.conf**: `ble_wifi_bridge/prj.conf` has hardcoded SSID/PSK
- **Extract debug_base.conf**: `debug_coredump.conf` and `debug_coredump_flash.conf` share ~15 lines of common config
- **Fold debug_config/ into crash_log/conf/**: `debug_config/` only holds two .conf files used exclusively with crash_log

### MCP Server Improvements
- **Make apps_dir configurable in zephyr-build**: Currently hardcoded to `zephyr-apps/apps` in config.rs — should accept CLI arg or config file override
- **Proportional documentation**: Reserve full README+PRD+CLAUDE for substantial components; small libraries (device_shell) only need CLAUDE.md
