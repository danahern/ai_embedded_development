# Learnings: MCP / Hardware Workflow

### RTT output arrives in chunks
When capturing coredump data via `rtt_read`, output arrives in ~1KB chunks. Concatenate all reads until `#CD:END#` appears before passing to `analyze_coredump`. Lines can split across chunk boundaries.

### ELF flashing can fail on nRF54L15 RRAM
probe-rs sometimes fails to flash ELF files on nRF54L15 (RRAM-based flash). Fall back to `.hex` files: `flash_program(session_id, file_path="build/zephyr/zephyr.hex")`.

### Coredump size and RTT buffer
`CONFIG_DEBUG_COREDUMP_MEMORY_DUMP_MIN=y` captures only the faulting thread's stack, which fits in the default 4KB RTT buffer. `MEMORY_DUMP_LINKER_RAM` captures all RAM and will overflow RTT — only use with flash backend.

### Log buffer drops during boot auto-report
When `crash_log` auto-emits a coredump at boot via `SYS_INIT`, the **Zephyr deferred log buffer** (not RTT buffer) overflows because boot messages from other subsystems compete. Symptom: "8 messages dropped" losing the `#CD:BEGIN#` and ZE header. Fix: increase `CONFIG_LOG_BUFFER_SIZE=4096` (default is 1024). Increasing `CONFIG_SEGGER_RTT_BUFFER_SIZE_UP` alone doesn't help — the bottleneck is the in-memory log message ring buffer.

### coredump_cmd return values
`coredump_cmd(COREDUMP_CMD_COPY_STORED_DUMP)` returns **positive byte count** on success, not 0. Check `if (ret <= 0)` for errors, and use `ret` as the actual bytes copied for iteration.

### nRF54L15 RRAM flash quirks
- `flash_program` with `.hex` works directly without prior erase
- `run_firmware` (erase+program) fails on nRF54L15 RRAM
- `flash_erase` followed by `flash_program` also fails
- `connect_under_reset=true` helps recover from stuck states
- nRF54L15 RRAM is exactly 1524KB (0x17D000). Default storage fills to the end — must shrink storage to fit a coredump partition

### In-memory coredump backend for testing
`CONFIG_DEBUG_COREDUMP_BACKEND_IN_MEMORY` provides the same query/copy API as the flash backend. Works on QEMU for unit testing crash_log without real flash hardware.
