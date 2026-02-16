---
paths: ['**/*provision_tool*.py', '**/.github/workflows/*.yml', '**/ble/*.py', '**/build_tools.rs', '**/probe-rs*', '**/pyproject.toml', '**/types.rs']
---
# Toolchain Learnings

- **bleak macOS: BLEDevice UUID expires between scans — use find_device helper** — On macOS, CoreBluetooth assigns UUIDs that can expire between BLE scan sessions. Passing a stale UUID string to `BleakClient(address)` raises `BleakDeviceNotFoundError`. Fix: always do a fresh `BleakScanner.discover()` and pass the `BLEDevice` object to `BleakClient(device)`. Use `return_adv=True` for advertisement data (RSSI). The `BLEDevice.rssi` attribute was removed in newer bleak versions.
- **probe-rs v0.31 CLI flags: --binary-format not --format, auto-detects from extension** — probe-rs v0.31 CLI has different flags than older versions and some common assumptions are wrong:
- **Per-board build directories in zephyr-build MCP** — Build directories changed from `apps/<name>/build/` to `apps/<name>/build/<board_sanitized>/` where `/` in board names becomes `_` (e.g., `nrf7002dk/nrf5340/cpuapp` → `nrf7002dk_nrf5340_cpuapp`). This prevents building for one board from wiping another board's artifacts. `clean(app)` removes all board builds; `clean(app, board)` removes just one. `list_apps()` now returns `built_boards` array instead of single `board` field.
- **Python MCP pyproject.toml must use setuptools.build_meta** — When creating Python MCP servers with setuptools, the build-backend must be `setuptools.build_meta`, not `setuptools.backends._legacy:_Backend`. The legacy backend causes installation failures. Follow the saleae-logic pattern: `[build-system]\nrequires = ["setuptools>=68.0"]\nbuild-backend = "setuptools.build_meta"`. Add dev dependencies in `[project.optional-dependencies]` for pytest.
