---
paths: ["**/*shell*", "**/build_tools.rs", "**/claude-mcps/**/*.py", "**/claude-mcps/**/*.rs", "**/hw_test_runner/**", "**/testcase.yaml", "**/tests/**"]
---
# Testing Learnings

- **MCP servers must have unit tests for core logic** — The workspace CLAUDE.md testing section says "Generated code must be unit tested" but this was interpreted as only applying to Zephyr apps/libraries, not MCP servers. This led to the knowledge-server shipping a bug in `next_sequence()` where the ID prefix format didn't match `generate_id()` output, causing every `capture()` call on the same day to overwrite the previous item.
- **native_sim is Linux-only** — The POSIX architecture (`native_sim`, `native_posix`) doesn't work on macOS. Use `qemu_cortex_m3` for unit tests that need an ARM target.
- **hw-test-runner MCP decouples BLE testing from probe-rs** — The hw-test-runner Python MCP server provides BLE and TCP testing that runs independently of probe-rs. BLE uses bleak (CoreBluetooth on macOS), so there's no J-Link conflict. This eliminates the disconnect/reconnect cycle when alternating between RTT debugging and BLE testing. Key tools: ble_discover, ble_read, ble_write, ble_subscribe, wifi_provision, wifi_scan_aps, wifi_status, wifi_factory_reset, tcp_throughput. Registered in .mcp.json with its own .venv.
- **Shell dummy backend for testing** — `CONFIG_SHELL_BACKEND_DUMMY=y` works well for testing shell commands without hardware. Pattern:
- **Twister pyenv fix now in zephyr-build MCP** — The zephyr-build MCP now strips `~/.pyenv/shims` from PATH before spawning twister. This fixes the JSON parsing failure caused by pyenv's python shim emitting error text to stderr (which cmake merges into stdout via stderr=subprocess.STDOUT). No manual PATH workaround needed anymore — `run_tests()` handles it automatically.
- **shell_execute_cmd returns 1 when help is printed** — When a shell command has a NULL handler (parent with subcommands only), the shell prints subcommand help and returns `SHELL_CMD_HELP_PRINTED` (1), not 0. Tests must call the full subcommand path (e.g., `"board info"` not `"board"`).
