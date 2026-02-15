# Embedded Development Workspace

## Collaboration Style

**This is a collaborative workspace. Ask questions and propose approaches before diving into implementation.**

- When given a new task, propose an approach first. Don't silently pick one path when multiple exist.
- Surface tradeoffs: "We could do X (simpler, less flexible) or Y (more work, more reusable) — which fits better?"
- If you hit something unexpected (a Zephyr API that doesn't work as expected, a build error with multiple possible fixes), explain what you found and ask which direction to go.
- When a task touches multiple subsystems (MCP server + Zephyr library + app), outline the pieces and confirm scope before starting.
- If you're unsure about a design choice (naming, architecture, where to put code), ask. A 30-second question saves a 30-minute rewrite.

## Learnings & Ideas

**Read `LEARNINGS.md` before starting new work.** It contains hard-won knowledge from past sessions.

- After completing a task that involved debugging surprises, non-obvious Zephyr behavior, or important architectural decisions, **summarize what you learned and add it to `LEARNINGS.md`**.
- New ideas for future work go in the "Ideas & Future Work" section at the bottom of `LEARNINGS.md`. Capture them so they don't get lost between sessions.

## CRITICAL: MCP-First Policy

**ALWAYS use MCP tools for operations they support. NEVER work around a broken or missing MCP tool by shelling out to CLI equivalents (addr2line, west, idf.py, nrfjprog, etc.).**

If an MCP tool call fails or a tool you expect to exist is not available:
1. **STOP and tell the user.** Explain which tool failed or is missing and why.
2. **Suggest the fix** — e.g., "The `analyze_coredump` tool is not available. The MCP server likely needs to be rebuilt and restarted after code changes. Run `cargo build --release` in `claude-mcps/embedded-probe/` and restart the MCP server."
3. **Do NOT silently fall back** to raw CLI commands, scripts, or manual hex parsing. The MCP tools exist so the user can trust a consistent workflow. Bypassing them hides bugs and defeats the purpose of having them.

This applies to all MCP servers: embedded-probe, zephyr-build, esp-idf-build, saleae-logic.

## MCP Servers - USE THESE FOR ALL OPERATIONS

### zephyr-build (Building)
ALWAYS use for build operations instead of running west directly:
- `list_apps()` - See available applications
- `list_boards(filter="nrf")` - Find target boards
- `build(app, board, pristine=true)` - Build firmware
- `build(app, board, background=true)` - Long builds in background
- `build_status(build_id)` - Check background build progress
- `clean(app)` - Remove build artifacts

### esp-idf-build (ESP-IDF Building & Flashing)
ALWAYS use for ESP-IDF build/flash operations instead of running idf.py directly:
- `list_projects(projects_dir="...")` - Scan for ESP-IDF projects
- `list_targets()` - Show supported ESP32 chips
- `set_target(project, target)` - Set target chip (e.g., "esp32p4")
- `build(project)` - Build project
- `build(project, background=true)` - Long builds in background
- `build_status(build_id)` - Check background build progress
- `flash(project, port="/dev/cu.usbserial-1110")` - Flash all segments
- `monitor(project, port, duration_seconds=10)` - Capture serial output
- `clean(project)` - Remove build artifacts

### saleae-logic (Logic Analyzer)
Use for signal capture, protocol decoding, and hardware signal analysis:
- `get_app_info()` - Check Logic 2 connection
- `list_devices()` - Find connected analyzers
- `start_capture(channels=[0,1], duration_seconds=2)` - Timed capture
- `start_capture(channels=[0], trigger_channel=0, trigger_type="falling")` - Triggered capture
- `wait_capture(capture_id)` - Wait for capture to complete
- `stop_capture(capture_id)` - Stop manual capture
- `add_analyzer(capture_id, "I2C", {"SCL": 0, "SDA": 1})` - Decode protocol
- `export_analyzer_data(capture_id, analyzer_index)` - Get decoded data
- `analyze_capture(capture_id, analyzer_index)` - Smart summary (errors, timing, addresses)
- `search_protocol_data(capture_id, analyzer_index, pattern="0x9F")` - Search decoded data
- `get_timing_info(capture_id, channel=0)` - Frequency, duty cycle, pulse widths
- `stream_capture(channels, duration, analyzer_name, settings)` - One-shot capture + decode
- `save_capture(capture_id, filepath)` / `load_capture(filepath)` - .sal file I/O
- `compare_captures(id_a, id_b, idx_a, idx_b)` - Diff captures for regression testing

### embedded-probe (Debug & Flash)
Use for all hardware interaction:
- `list_probes()` - Find connected debug probes
- `connect(probe_selector="auto", target_chip="nrf54l15")` - Attach
- `flash_program(session_id, file_path)` - Flash firmware
- `validate_boot(session_id, file_path, success_pattern="Booting Zephyr")` - Flash + verify boot
- `rtt_read(session_id)` - Read RTT output
- `reset(session_id)` - Reset target
- `resolve_symbol(address, elf_path)` - Resolve address to function name + source line
- `stack_trace(session_id, elf_path)` - Walk stack with symbol resolution
- `analyze_coredump(log_text, elf_path)` - Parse Zephyr `#CD:` coredump from RTT, return crash report

## Typical Workflow (Zephyr)

1. **Build**: `zephyr-build.build(app="ble_wifi_bridge", board="nrf52840dk/nrf52840", pristine=true)`
2. **Connect**: `embedded-probe.connect(probe_selector="auto", target_chip="nRF52840_xxAA")`
3. **Flash + Validate**: `embedded-probe.validate_boot(session_id, file_path="...zephyr.elf", success_pattern="Booting Zephyr")`
4. **Monitor**: `embedded-probe.rtt_read(session_id)` - Check runtime output

## Typical Workflow (ESP-IDF)

1. **Set Target**: `esp-idf-build.set_target(project="esp32-p4-eye/factory", target="esp32p4")`
2. **Build**: `esp-idf-build.build(project="esp32-p4-eye/factory")`
3. **Flash**: `esp-idf-build.flash(project="esp32-p4-eye/factory", port="/dev/cu.usbserial-1110")`
4. **Monitor**: `esp-idf-build.monitor(project="esp32-p4-eye/factory", port="/dev/cu.usbserial-1110", duration_seconds=10)`

## Typical Workflow (Crash Debug)

Requires: app includes `lib/debug_config/debug_coredump.conf` overlay for coredump+RTT support.

1. **Build**: `zephyr-build.build(app="crash_debug", board="nrf54l15dk/nrf54l15/cpuapp", pristine=true)`
2. **Connect**: `embedded-probe.connect(probe_selector="auto", target_chip="nrf54l15")`
3. **Flash**: `embedded-probe.flash_program(session_id, file_path="build/zephyr/zephyr.hex")` - Use .hex if .elf fails on nRF54L15
4. **Reset + RTT**: `embedded-probe.reset(session_id, halt_after_reset=false)` then `embedded-probe.rtt_attach(session_id)`
5. **Capture**: `embedded-probe.rtt_read(session_id, timeout_ms=12000, max_bytes=16384)` - Repeat until `#CD:END#` appears (output arrives in ~1KB chunks)
6. **Analyze**: `embedded-probe.analyze_coredump(log_text=<combined_rtt_output>, elf_path="build/zephyr/zephyr.elf")` - Returns crash PC, function name, call chain
7. **Manual fallback**: `embedded-probe.resolve_symbol(address="0x...", elf_path="...zephyr.elf")` or `embedded-probe.stack_trace(session_id, elf_path="...")`

**Important notes:**
- RTT output arrives in ~1KB chunks. Concatenate all reads until `#CD:END#` is found before passing to `analyze_coredump`.
- Watch for hex data split across chunk boundaries — lines can break mid-hex-string.
- ELF flashing via probe-rs sometimes fails on nRF54L15 RRAM. Fall back to `.hex` file.
- The coredump uses `CONFIG_DEBUG_COREDUMP_MEMORY_DUMP_MIN=y` (stack only) to fit in the 4KB RTT buffer.

## Typical Workflow (Signal Analysis)

1. **Capture**: `saleae-logic.start_capture(channels=[0,1], duration_seconds=2)`
2. **Wait**: `saleae-logic.wait_capture(capture_id)`
3. **Decode**: `saleae-logic.add_analyzer(capture_id, "I2C", {"SCL": 0, "SDA": 1})`
4. **Analyze**: `saleae-logic.analyze_capture(capture_id, analyzer_index)`
5. **Search**: `saleae-logic.search_protocol_data(capture_id, analyzer_index, pattern="0x48")`

## Workspace Structure

| Directory | Purpose | Git |
|-----------|---------|-----|
| `claude-config/` | Claude Code skills and configuration | Submodule |
| `claude-mcps/` | MCP servers (embedded-probe, zephyr-build, esp-idf-build, saleae-logic) | Submodule |
| `zephyr-apps/` | Zephyr applications and west manifest | Submodule |
| `esp-dev-kits/` | ESP-IDF example projects for dev kits | Cloned |
| `test-tools/` | Python testing utilities | Tracked |
| `zephyr/` | Zephyr RTOS source | West-managed (gitignored) |
| `bootloader/` | MCUboot bootloader | West-managed (gitignored) |
| `modules/` | Zephyr modules (HAL, etc.) | West-managed (gitignored) |
| `tools/` | West tools (EDTT, net-tools) | West-managed (gitignored) |

## Key Files

- `setup.sh` - Automated workspace setup script
- `.gitignore` - Excludes west-managed dependencies
- `.gitmodules` - Submodule configuration

## Best Practices

Use `/embedded` command for full embedded development guidelines covering:
- Static memory allocation
- Error handling patterns
- Zephyr RTOS patterns
- MCP tool usage for building and debugging

## Common Boards

| Board | target_chip | Use Case |
|-------|-------------|----------|
| nrf52840dk/nrf52840 | nRF52840_xxAA | BLE development |
| nrf5340dk/nrf5340/cpuapp | nRF5340_xxAA | BLE + net core |
| nrf54l15dk/nrf54l15/cpuapp | nrf54l15 | Low-power BLE, crash debug |
| esp32_devkitc/esp32/procpu | ESP32 | WiFi + BLE |
| esp32s3_eye/esp32s3/procpu | ESP32-S3 | WiFi + BLE + camera |
| nucleo_g431rb | STM32G431RBTx | Motor control, ADC |
| native_sim | - | Unit testing |
