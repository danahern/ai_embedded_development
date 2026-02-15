---
paths: ["**/tests/**", "**/*test*", "**/testcase.yaml"]
---
# Testing Learnings

- **native_sim is Linux-only** — use `qemu_cortex_m3` for unit tests on macOS.
- **Shell dummy backend for testing** — `CONFIG_SHELL_BACKEND_DUMMY=y` with `shell_backend_dummy_get_ptr()` and `shell_execute_cmd()`.
- **shell_execute_cmd returns 1 = help printed** — parent commands with NULL handler return `SHELL_CMD_HELP_PRINTED` (1). Call full subcommand path.
- **Twister needs Zephyr SDK env vars** — MCP subprocesses don't inherit shell profile. Auto-detected from `~/.cmake/packages/Zephyr-sdk/`.
- **Core template libraries break QEMU** — crash_log/device_shell overlays enable RTT and flash. Remove `OVERLAY_CONFIG` lines for QEMU-only apps.
