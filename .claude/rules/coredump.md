---
paths: ["**/*crash*", "**/*coredump*", "**/*dump*"]
---
# Coredump Learnings

- **Two strategies**: RTT-only (simple, no flash) vs flash-backed (persists, needs DTS overlay with `coredump_partition`).
- **MEMORY_DUMP_MIN captures only faulting thread** — fits in 4KB RTT buffer. LINKER_RAM captures all RAM, overflows RTT.
- **coredump_cmd returns positive byte count on success** — check `if (ret <= 0)` for errors.
- **Log buffer drops boot auto-report** — `CONFIG_LOG_BUFFER_SIZE=4096` (default 1024 overflows). Bottleneck is deferred log buffer, not RTT.
- **Exception frame registers are the crash site** — coredump captures PC/LR/SP from ARM exception frame, not fault handler context.
- **In-memory backend for testing** — `CONFIG_DEBUG_COREDUMP_BACKEND_IN_MEMORY` works on QEMU for unit testing without real flash.
- **Flash-dependent code can't run on QEMU** — `BACKEND_FLASH_PARTITION` requires `FLASH_HAS_DRIVER_ENABLED`. Use `build_only: true` for real boards.
