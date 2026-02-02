# Embedded Development Workspace

This is the top-level workspace for embedded development with Zephyr RTOS.

## Directory Structure

| Directory | Purpose | Git |
|-----------|---------|-----|
| `claude-config/` | Claude Code skills and configuration | Submodule |
| `claude-mcps/` | MCP servers (embedded-probe) | Submodule |
| `zephyr-apps/` | Zephyr applications and west manifest | Submodule |
| `test-tools/` | Python testing utilities | Tracked |
| `zephyr/` | Zephyr RTOS source | West-managed (gitignored) |
| `bootloader/` | MCUboot bootloader | West-managed (gitignored) |
| `modules/` | Zephyr modules (HAL, etc.) | West-managed (gitignored) |
| `tools/` | West tools (EDTT, net-tools) | West-managed (gitignored) |

## Key Files

- `setup.sh` - Automated workspace setup script
- `.gitignore` - Excludes west-managed dependencies
- `.gitmodules` - Submodule configuration (after remotes added)

## Development Guidelines

When working on embedded code, use the `/embedded` skill from claude-config for guidelines on:
- Static memory allocation
- Error handling patterns
- Zephyr RTOS patterns

## Building

```bash
source zephyr-apps/.venv/bin/activate
cd zephyr-apps
west build -b <board> apps/<app-name> --pristine
```

## Common Boards

- `esp32_devkitc/esp32/procpu` - ESP32 DevKit
- `nrf52840dk/nrf52840` - Nordic nRF52840 DK
- `nucleo_g431rb` - STM32 Nucleo G4
