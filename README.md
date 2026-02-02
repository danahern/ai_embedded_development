# Embedded Development Workspace

Complete workspace for embedded development with Claude Code assistance, Zephyr RTOS, and hardware debugging.

## Quick Start

```bash
# Clone with submodules
git clone --recursive https://github.com/<username>/embedded-workspace.git
cd embedded-workspace

# Initialize west and fetch Zephyr dependencies
cd zephyr-apps
west init -l .
west update
cd ..

# Set up Python environment
python3 -m venv zephyr-apps/.venv
source zephyr-apps/.venv/bin/activate
pip install -r zephyr-apps/requirements.txt
```

## Structure

```
embedded-workspace/
├── claude-config/      # Claude Code configuration and skills (submodule)
├── claude-mcps/        # MCP servers (submodule)
│   └── embedded-probe/ # Debug/flash MCP (27 tools)
├── zephyr-apps/        # Zephyr applications (submodule, west manifest)
│   └── apps/           # Application code
├── test-tools/         # Testing utilities (Python)
│
├── zephyr/             # (west-managed, gitignored)
├── bootloader/         # (west-managed, gitignored)
├── modules/            # (west-managed, gitignored)
└── tools/              # (west-managed, gitignored)
```

## Submodules

| Submodule | Description |
|-----------|-------------|
| `claude-config` | Claude Code skills and configuration |
| `claude-mcps` | MCP servers for hardware debugging |
| `zephyr-apps` | Zephyr RTOS applications and west manifest |

## Setup from Scratch

### 1. Clone and Initialize

```bash
git clone --recursive <repo-url>
cd embedded-workspace
```

### 2. Set Up West (Zephyr Build System)

```bash
cd zephyr-apps
west init -l .
west update
cd ..
```

### 3. Set Up Python Environment

```bash
python3 -m venv zephyr-apps/.venv
source zephyr-apps/.venv/bin/activate
pip install west
pip install -r zephyr-apps/requirements.txt
```

### 4. Install Zephyr SDK

Follow [Zephyr Getting Started](https://docs.zephyrproject.org/latest/develop/getting_started/index.html) for SDK installation.

### 5. Build MCP Server (Optional)

```bash
cd claude-mcps/embedded-probe
cargo build --release
```

## Building Firmware

```bash
# Activate environment
source zephyr-apps/.venv/bin/activate

# Build for a specific board
cd zephyr-apps
west build -b <board> apps/<app-name> --pristine

# Example: ESP32
west build -b esp32_devkitc/esp32/procpu apps/ble_wifi_bridge --pristine

# Example: nRF52840
west build -b nrf52840dk/nrf52840 apps/my_app --pristine
```

## Updating

```bash
# Update submodules
git submodule update --remote

# Update west dependencies
cd zephyr-apps && west update
```

## Claude Code Integration

Link claude-config for Claude Code to use the embedded development skill:
```bash
ln -s $(pwd)/claude-config ~/.claude
```

Configure embedded-probe MCP in Claude Code settings.

## Related Documentation

- [claude-config/README.md](claude-config/README.md) - Claude skills
- [claude-mcps/README.md](claude-mcps/README.md) - MCP servers
- [zephyr-apps/README.md](zephyr-apps/README.md) - Zephyr applications
- [test-tools/README.md](test-tools/README.md) - Testing utilities
