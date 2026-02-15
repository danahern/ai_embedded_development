---
paths: ["**/*shell*", "**/testcase.yaml", "**/tests/**"]
---
# Testing Learnings

- **native_sim is Linux-only** — The POSIX architecture (`native_sim`, `native_posix`) doesn't work on macOS. Use `qemu_cortex_m3` for unit tests that need an ARM target.
- **Shell dummy backend for testing** — `CONFIG_SHELL_BACKEND_DUMMY=y` works well for testing shell commands without hardware. Pattern:
- **shell_execute_cmd returns 1 when help is printed** — When a shell command has a NULL handler (parent with subcommands only), the shell prints subcommand help and returns `SHELL_CMD_HELP_PRINTED` (1), not 0. Tests must call the full subcommand path (e.g., `"board info"` not `"board"`).
