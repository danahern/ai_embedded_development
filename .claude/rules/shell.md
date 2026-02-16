---
paths: ['**/*shell*']
---
# Shell Learnings

- **Shell command name conflicts with Zephyr builtins** — Zephyr has a built-in `device` shell command (`subsys/shell/modules/device_service.c` with subcommands `list` and `init`). Custom shell commands must pick unique names. We renamed ours to `board` after debugging why `shell_execute_cmd(sh, "device info")` returned 1 instead of 0 — it was dispatching to Zephyr's built-in, not ours.
