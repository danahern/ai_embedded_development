# Embedded Development Workspace

## Collaboration Style
- Act like a senior engineer, evalute requests, if there is a better way propose it.  This is a collaborative project.

**Ask questions and propose approaches before diving into implementation.**

- Propose an approach first when multiple paths exist. Surface tradeoffs.
- If you hit something unexpected, explain what you found and ask which direction to go.
- When a task touches multiple subsystems, outline the pieces and confirm scope before starting.

## Key Gotchas

Hard-won lessons (Tier 1 — always loaded). Full details via `knowledge.search()` or `/recall`.

- **nRF54L15**: Use `.hex` not `.elf` for flashing. `flash_program` works; `run_firmware` (erase+program) fails. Use `connect_under_reset=true` to recover stuck states.
- **Log buffer drops**: Boot-time coredump auto-report drops messages if `CONFIG_LOG_BUFFER_SIZE` is too small (default 1024). Set to 4096+. The bottleneck is the deferred log buffer, not the RTT buffer.
- **RTT chunks**: Output arrives in ~1KB chunks. Concatenate all reads until `#CD:END#` before passing to `analyze_coredump`.
- **Shell naming**: Zephyr has a built-in `device` shell command. Pick unique names for custom commands.
- **RTT buffer conflict**: `LOG_BACKEND_RTT` and `SHELL_BACKEND_RTT` both default to buffer 0. Set `SHELL_BACKEND_RTT_BUFFER=1`.
- **native_sim**: Linux-only. Use `qemu_cortex_m3` for unit tests on macOS.
- **module.yml paths**: Relative to module root (parent of `zephyr/`), not relative to the yml file.
- **Board qualifiers**: `/` in CMake (`nrf52840dk/nrf52840`), `_` in overlay filenames (`nrf52840dk_nrf52840.overlay`). Let Zephyr auto-discover overlays from `boards/`.
- **coredump_cmd return**: `COREDUMP_CMD_COPY_STORED_DUMP` returns positive byte count on success, not 0.
- **Build dirs are per-board**: Each app builds to `apps/<name>/build/<board_sanitized>/` (e.g., `build/nrf52840dk_nrf52840/`). Multiple boards can coexist without wiping each other's artifacts.
- **Twister SDK env vars**: MCP subprocesses don't inherit shell profile env vars. The `run_tests` tool auto-detects the SDK from `~/.cmake/packages/Zephyr-sdk/`. If that fails, set `ZEPHYR_TOOLCHAIN_VARIANT=zephyr` and `ZEPHYR_SDK_INSTALL_DIR` in the MCP launch environment.
- **QEMU + core template**: `create_app` core template includes crash_log/device_shell overlays that require RTT and flash — unavailable on `qemu_cortex_m3`. Remove `OVERLAY_CONFIG` lines for QEMU-only apps.
- **Flash backend needs real hardware**: `CONFIG_DEBUG_COREDUMP_BACKEND_FLASH_PARTITION` requires `FLASH_HAS_DRIVER_ENABLED`. Won't build on QEMU — use `build_only: true` with `platform_allow` for real boards.
- **Gitignore negation**: `.claude/` (trailing slash) makes git skip the entire directory. Use `.claude/*` with `!.claude/rules/` to allow negation.
- **ESP32 WiFi power management**: Modem sleep blocks incoming TCP/ping even though ARP resolves. Call `esp_wifi_set_ps(WIFI_PS_NONE)` after `esp_wifi_start()` for reliable incoming connections.
- **ESP32 FreeRTOS stack sizes**: `StackType_t` is `uint8_t` on Xtensa ESP32 — `xTaskCreate` stack_depth is in bytes, not words. 2048 = 2KB, not 8KB. Use 4096+ for tasks calling WiFi APIs.
- **BLE GATT callbacks**: Must not block. Defer WiFi connect, NVS writes, factory reset to work queue. Copy data to static buffer before submitting work.
- **qemu_cortex_m3 has no flash driver**: lm3s6965 has no flash driver in Zephyr — NVS/Settings cannot work. Use `mps2/an385` for Settings/NVS tests. Use `platform_allow` in testcase.yaml (not just `integration_platforms`).

## CRITICAL: MCP-First Policy

**ALWAYS use MCP tools for operations they support. NEVER shell out to CLI equivalents (addr2line, west, idf.py, nrfjprog, etc.).**

If an MCP tool fails:
1. **STOP and tell the user.** Explain which tool failed and why.
2. **Suggest the fix** — e.g., rebuild the MCP server and restart.
3. **Do NOT silently fall back** to raw CLI commands.

## MCP Servers

Tool signatures are in each server's own CLAUDE.md (`claude-mcps/<server>/CLAUDE.md`). Available servers:

- **zephyr-build** — Build, test, scaffold Zephyr apps (west wrapper)
- **elf-analysis** — ROM/RAM size analysis, diffing, top consumers
- **esp-idf-build** — ESP-IDF build, flash, monitor
- **linux-build** — Docker cross-compilation, SSH/ADB deployment, Yocto builds
- **embedded-probe** — Debug probes, flash programming, RTT, coredump analysis, nrfutil
- **knowledge** — Knowledge capture, search, board profiles, rule/gotcha regeneration
- **saleae-logic** — Logic analyzer capture and protocol decoding
- **hw-test-runner** — BLE GATT, WiFi provisioning, TCP throughput testing

Board details available via `knowledge.board_info("board_name")` or `knowledge.list_boards()`.

## Typical Workflows

### Zephyr (Build-Flash-Test)
1. `zephyr-build.build(app, board, pristine=true)`
2. `embedded-probe.connect(probe_selector="auto", target_chip="...")`
3. `embedded-probe.validate_boot(session_id, file_path, success_pattern="Booting Zephyr")`
4. `embedded-probe.rtt_read(session_id)`

### ESP-IDF
1. `esp-idf-build.set_target(project, target)` → `build(project)` → `flash(project, port)` → `monitor(project, port, duration_seconds=10)`

### Crash Debug
1. Build, connect, flash `.hex`, reset with `halt_after_reset=false`, attach RTT
2. Read RTT until `#CD:END#` (concatenate chunks)
3. `embedded-probe.analyze_coredump(log_text, elf_path)` → crash PC, function, call chain

### Unit Tests
1. `zephyr-build.run_tests(board="qemu_cortex_m3")` — all lib tests
2. `zephyr-build.test_results(test_id=...)` — structured pass/fail

## Plans

Plans in `plans/` track significant work (new MCPs, skills, agents, apps, libs, or changes touching 5+ files). Status lifecycle: `Ideation` → `Planned` → `In-Progress` → `Complete`. Descriptive kebab-case names, git-tracked.

**Rules:** Create plan file BEFORE starting implementation. Update incrementally during work. Never mark Complete until all verification passes. The `plans/` file is the single source of truth — not session drafts.

## Project Documentation

- **Significant components** (MCPs, skills, agents, apps, libs) — `README.md` + `PRD.md` + `CLAUDE.md` + plan
- **Small components** — `CLAUDE.md` only is sufficient

## Testing

**All code must be unit tested — apps, libraries, AND MCP servers.** Test failure cases, not just happy path. Cover edge cases: invalid input, missing files, empty data, error conditions. MCP servers: test core logic (ID generation, parsing, encoding) — these bugs are silent and destructive.

## Knowledge

Three-tier retrieval delivers the right knowledge at the right time:

| Tier | What | Where | When |
|------|------|-------|------|
| 1 | Critical gotchas | `CLAUDE.md` Key Gotchas section | Every session, always in context |
| 2 | Topic rules | `.claude/rules/*.md` (auto-generated) | Auto-injected when editing matching files |
| 3 | Full corpus | `knowledge/items/*.yml` | On-demand via `/recall` or `knowledge.search()` |

Capture with `/learn` or `/wrap-up`. Regenerate derived files with `knowledge.regenerate_gotchas()` (Tier 1) and `knowledge.regenerate_rules()` (Tier 2).

## Workspace Structure

`firmware/` (Zephyr/ESP-IDF apps + shared libs), `claude-mcps/` (MCP servers, submodule), `claude-config/` (skills/agents, submodule), `knowledge/` (items + board profiles), `test-tools/` (Python BLE/power utils), `plans/` + `retrospective/`. West-managed deps: `zephyr/`, `bootloader/`, `modules/`, `tools/` (gitignored).

## Key Commands

- `/start` — Bootstrap session (recent knowledge, hardware check, git status)
- `/wrap-up` — End session (capture knowledge, commit work)
- `/learn` — Capture a knowledge item with metadata and tags
- `/recall` — Search knowledge by topic, tag, or keyword
- `/embedded` — Full embedded development guidelines (memory, style, Zephyr patterns)
- `/bft <app> <board>` — Build, flash, validate boot, read output — single command inner loop
- `/hw-verify <app> <board>` — Guided hardware verification checklist
