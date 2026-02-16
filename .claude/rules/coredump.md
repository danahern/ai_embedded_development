---
paths: ["**/*.conf", "**/*coredump*", "**/*crash*", "**/*dump*", "**/Kconfig*", "**/testcase.yaml", "**/tests/**"]
---
# Coredump Learnings

- **Flash-dependent code can't run on QEMU** — `CONFIG_DEBUG_COREDUMP_BACKEND_FLASH_PARTITION` requires `FLASH_HAS_DRIVER_ENABLED` which QEMU doesn't provide. For tests that need flash, use `build_only: true` with `platform_allow` for real boards, or find an alternative test strategy.
- **Log buffer drops during boot auto-report** — When `crash_log` auto-emits a coredump at boot via `SYS_INIT`, the Zephyr deferred log buffer (not RTT buffer) overflows because boot messages from other subsystems compete. Symptom: "8 messages dropped" losing the `#CD:BEGIN#` and ZE header. Fix: increase `CONFIG_LOG_BUFFER_SIZE=4096` (default is 1024). Increasing `CONFIG_SEGGER_RTT_BUFFER_SIZE_UP` alone doesn't help — the bottleneck is the in-memory log message ring buffer.
- **Zephyr coredump captures exception frame registers** — The coredump subsystem captures PC/LR/SP from the ARM exception frame — the actual crash site. This is better than halting after a fault and reading registers, which only shows the fault handler context.
- **coredump_cmd return values** — `coredump_cmd(COREDUMP_CMD_COPY_STORED_DUMP)` returns positive byte count on success, not 0. Check `if (ret <= 0)` for errors, and use `ret` as the actual bytes copied for iteration.
- **In-memory coredump backend for testing** — `CONFIG_DEBUG_COREDUMP_BACKEND_IN_MEMORY` provides the same query/copy API as the flash backend. Works on QEMU for unit testing crash_log without real flash hardware.
