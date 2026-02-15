# Learnings

Hard-won knowledge from building in this workspace. Read before starting new work.

## Zephyr Build System

### module.yml paths are relative to module root, not the yml file
`zephyr/module.yml` paths (`cmake:`, `kconfig:`) resolve relative to the module root (the parent of `zephyr/`), not relative to `module.yml` itself. Use `cmake: .` and `kconfig: Kconfig`, not `cmake: ..` / `kconfig: ../Kconfig`.

### Board qualifiers: `/` in CMake, `_` in filenames
`${BOARD}` expands to `nrf52840dk/nrf52840` (with `/`) but DTS overlay files use `_` separator: `nrf52840dk_nrf52840.overlay`. Don't set `DTC_OVERLAY_FILE` manually — put overlays in the app's `boards/` directory and let Zephyr auto-discover them.

### Shell command name conflicts
Zephyr has a built-in `device` shell command (`subsys/shell/modules/device_service.c` with subcommands `list` and `init`). Custom shell commands must pick unique names. We renamed ours to `board` after debugging why `shell_execute_cmd(sh, "device info")` returned 1 instead of 0 — it was dispatching to Zephyr's built-in, not ours.

### RTT buffer conflicts
`CONFIG_LOG_BACKEND_RTT` and `CONFIG_SHELL_BACKEND_RTT` both default to buffer 0. When using both, set `CONFIG_SHELL_BACKEND_RTT_BUFFER=1` or the build fails with "Conflicting log RTT backend enabled on the same channel."

### OVERLAY_CONFIG vs DTC_OVERLAY_FILE
`OVERLAY_CONFIG` is for Kconfig fragments (`.conf` files). `DTC_OVERLAY_FILE` is for devicetree overlays (`.overlay` files). Zephyr auto-discovers DTS overlays from `boards/` but you must explicitly list Kconfig overlays via `OVERLAY_CONFIG`.

## Testing on macOS

### native_sim is Linux-only
The POSIX architecture (`native_sim`, `native_posix`) doesn't work on macOS. Use `qemu_cortex_m3` for unit tests that need an ARM target.

### Flash-dependent code can't run on QEMU
`CONFIG_DEBUG_COREDUMP_BACKEND_FLASH_PARTITION` requires `FLASH_HAS_DRIVER_ENABLED` which QEMU doesn't provide. For tests that need flash, use `build_only: true` with `platform_allow` for real boards, or find an alternative test strategy.

### Shell dummy backend for testing
`CONFIG_SHELL_BACKEND_DUMMY=y` works well for testing shell commands without hardware. Pattern:
```c
const struct shell *sh = shell_backend_dummy_get_ptr();
shell_execute_cmd(sh, "board info");
const char *output = shell_backend_dummy_get_output(sh, &size);
zassert_not_null(strstr(output, "Board:"), "expected Board: in output");
```

### shell_execute_cmd returns 1 = help printed
When a shell command has a NULL handler (parent with subcommands only), the shell prints subcommand help and returns `SHELL_CMD_HELP_PRINTED` (1), not 0. Tests must call the full subcommand path (e.g., `"board info"` not `"board"`).

## MCP / Hardware Workflow

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

## Architecture Decisions

### Two coredump strategies
- **RTT-only** (`debug_coredump.conf`): Simple, no flash partition needed. Data streams through RTT at crash time. Lost if no one is reading.
- **Flash-backed** (`debug_coredump_flash.conf`): Persists to flash, survives reboot. `crash_log` module re-emits on next boot. Needs a DTS overlay with `coredump_partition`.

### Zephyr coredump captures exception frame registers
The coredump subsystem captures PC/LR/SP from the ARM exception frame — the actual crash site. This is better than halting after a fault and reading registers, which only shows the fault handler context.

---

# Ideas & Future Work

Potential directions. Not committed — just captured so they don't get lost.

## CI Pipeline
Automated builds on push. QEMU tests run automatically, hardware tests triggered manually. Could use GitHub Actions with self-hosted runners for hardware.

## ESP-IDF Crash Analysis
ESP-IDF has its own coredump format (different from Zephyr). Could extend `analyze_coredump` to detect and handle ESP32 core dumps, or add a separate `analyze_esp_coredump` tool.

## New Library Ideas
Candidates based on patterns that keep repeating:
- **BLE NUS abstraction** — Already exists in `ble_wifi_bridge`, could extract to a shared library
- **Logging configuration helper** — Standardize RTT vs UART vs both
- **OTA DFU shell commands** — MCUboot-based firmware update management via shell
