# Embedded Development Workspace

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

### embedded-probe (Debug & Flash)
Use for all hardware interaction:
- `list_probes()` - Find connected debug probes
- `connect(probe_selector="auto", target_chip="nRF52840_xxAA")` - Attach
- `flash_program(session_id, file_path)` - Flash firmware
- `validate_boot(session_id, file_path, success_pattern="Booting Zephyr")` - Flash + verify boot
- `rtt_read(session_id)` - Read RTT output
- `reset(session_id)` - Reset target

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

## Workspace Structure

| Directory | Purpose | Git |
|-----------|---------|-----|
| `claude-config/` | Claude Code skills and configuration | Submodule |
| `claude-mcps/` | MCP servers (embedded-probe, zephyr-build, esp-idf-build) | Submodule |
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
| esp32_devkitc/esp32/procpu | ESP32 | WiFi + BLE |
| esp32s3_eye/esp32s3/procpu | ESP32-S3 | WiFi + BLE + camera |
| nucleo_g431rb | STM32G431RBTx | Motor control, ADC |
| native_sim | - | Unit testing |
