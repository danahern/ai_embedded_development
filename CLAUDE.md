# Embedded Development Workspace

## Collaboration Style

**Ask questions and propose approaches before diving into implementation.**

- Propose an approach first when multiple paths exist. Surface tradeoffs.
- If you hit something unexpected, explain what you found and ask which direction to go.
- When a task touches multiple subsystems, outline the pieces and confirm scope before starting.

## Key Gotchas

Hard-won lessons. Full details in `LEARNINGS.md`.

- **nRF54L15**: Use `.hex` not `.elf` for flashing. `flash_program` works; `run_firmware` (erase+program) fails. Use `connect_under_reset=true` to recover stuck states.
- **Log buffer drops**: Boot-time coredump auto-report drops messages if `CONFIG_LOG_BUFFER_SIZE` is too small (default 1024). Set to 4096+. The bottleneck is the deferred log buffer, not the RTT buffer.
- **RTT chunks**: Output arrives in ~1KB chunks. Concatenate all reads until `#CD:END#` before passing to `analyze_coredump`.
- **Shell naming**: Zephyr has a built-in `device` shell command. Pick unique names for custom commands.
- **RTT buffer conflict**: `LOG_BACKEND_RTT` and `SHELL_BACKEND_RTT` both default to buffer 0. Set `SHELL_BACKEND_RTT_BUFFER=1`.
- **native_sim**: Linux-only. Use `qemu_cortex_m3` for unit tests on macOS.
- **module.yml paths**: Relative to module root (parent of `zephyr/`), not relative to the yml file.
- **Board qualifiers**: `/` in CMake (`nrf52840dk/nrf52840`), `_` in overlay filenames (`nrf52840dk_nrf52840.overlay`). Let Zephyr auto-discover overlays from `boards/`.
- **coredump_cmd return**: `COREDUMP_CMD_COPY_STORED_DUMP` returns positive byte count on success, not 0.
- **Build dirs are per-app**: Each app builds to `apps/<name>/build/`. The zephyr-build MCP passes `-d` automatically.

## Learnings & Ideas

**Run `/start` at the beginning of a session** to bootstrap context (reads LEARNINGS.md, shows recent activity, checks hardware).

**Run `/wrap-up` at the end of a session** to capture learnings and commit work.

After debugging surprises or non-obvious behavior, add findings to `LEARNINGS.md`.

## CRITICAL: MCP-First Policy

**ALWAYS use MCP tools for operations they support. NEVER shell out to CLI equivalents (addr2line, west, idf.py, nrfjprog, etc.).**

If an MCP tool fails:
1. **STOP and tell the user.** Explain which tool failed and why.
2. **Suggest the fix** — e.g., rebuild the MCP server and restart.
3. **Do NOT silently fall back** to raw CLI commands.

## MCP Servers

### zephyr-build (Building)
- `list_apps()`, `list_boards(filter="nrf")`, `build(app, board, pristine=true)`, `build(app, board, background=true)`, `build_status(build_id)`, `clean(app)`

### esp-idf-build (ESP-IDF)
- `list_projects()`, `list_targets()`, `set_target(project, target)`, `build(project)`, `flash(project, port)`, `monitor(project, port, duration_seconds)`, `clean(project)`

### embedded-probe (Debug & Flash)
- `list_probes()`, `connect(probe_selector, target_chip)`, `flash_program(session_id, file_path)`, `validate_boot(session_id, file_path, success_pattern)`, `rtt_attach(session_id)`, `rtt_read(session_id)`, `reset(session_id)`, `resolve_symbol(address, elf_path)`, `stack_trace(session_id, elf_path)`, `analyze_coredump(log_text, elf_path)`

### saleae-logic (Logic Analyzer)
- `get_app_info()`, `list_devices()`, `start_capture(channels, duration_seconds)`, `wait_capture(capture_id)`, `add_analyzer(capture_id, analyzer_name, settings)`, `export_analyzer_data(capture_id, analyzer_index)`, `analyze_capture(capture_id, analyzer_index)`, `stream_capture(channels, duration, analyzer_name, settings)`

## Typical Workflows

### Zephyr
1. `zephyr-build.build(app, board, pristine=true)`
2. `embedded-probe.connect(probe_selector="auto", target_chip="...")`
3. `embedded-probe.validate_boot(session_id, file_path, success_pattern="Booting Zephyr")`
4. `embedded-probe.rtt_read(session_id)`

### ESP-IDF
1. `esp-idf-build.set_target(project, target)`
2. `esp-idf-build.build(project)`
3. `esp-idf-build.flash(project, port)`
4. `esp-idf-build.monitor(project, port, duration_seconds=10)`

### Crash Debug
1. Build with `zephyr-build.build(app="crash_debug", board="nrf54l15dk/nrf54l15/cpuapp")`
2. Connect, flash `.hex`, reset with `halt_after_reset=false`, attach RTT
3. Read RTT until `#CD:END#` (concatenate chunks)
4. `embedded-probe.analyze_coredump(log_text, elf_path)` → crash PC, function, call chain

### Signal Analysis
1. `saleae-logic.start_capture(channels=[0,1], duration_seconds=2)`
2. `saleae-logic.wait_capture(capture_id)`
3. `saleae-logic.add_analyzer(capture_id, "I2C", {"SCL": 0, "SDA": 1})`
4. `saleae-logic.analyze_capture(capture_id, analyzer_index)`

### Testing
```bash
python3 zephyr/scripts/twister -T zephyr-apps/tests -p qemu_cortex_m3 -v
```

## Common Boards

| Board | target_chip | Use Case |
|-------|-------------|----------|
| nrf52840dk/nrf52840 | nRF52840_xxAA | BLE development |
| nrf5340dk/nrf5340/cpuapp | nRF5340_xxAA | BLE + net core |
| nrf54l15dk/nrf54l15/cpuapp | nrf54l15 | Low-power BLE, crash debug |
| esp32_devkitc/esp32/procpu | ESP32 | WiFi + BLE |
| esp32s3_eye/esp32s3/procpu | ESP32-S3 | WiFi + BLE + camera |
| native_sim | - | Unit testing (Linux only) |
| qemu_cortex_m3 | - | Unit testing (cross-platform) |

## Workspace Structure

| Directory | Purpose | Git |
|-----------|---------|-----|
| `claude-config/` | Skills (`/embedded`, `/start`, `/wrap-up`) and settings | Submodule |
| `claude-mcps/` | MCP servers (embedded-probe, zephyr-build, esp-idf-build, saleae-logic) | Submodule |
| `zephyr-apps/` | Zephyr apps, shared libraries, tests | Submodule |
| `esp-dev-kits/` | ESP-IDF example projects | Cloned |
| `test-tools/` | Python BLE/power testing utilities | Tracked |
| `zephyr/`, `bootloader/`, `modules/`, `tools/` | West-managed dependencies | Gitignored |

## Key Commands

- `/start` — Bootstrap a session (read learnings, check hardware, show recent changes)
- `/wrap-up` — End a session (review changes, update learnings, commit)
- `/embedded` — Full embedded development guidelines (memory, style, Zephyr patterns)
