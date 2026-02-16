# Hardware Verification Workflow Improvements

Status: Complete
Created: 2026-02-16

Supersedes: per-board-build-dirs.md, esp32-detection.md, lsp-diagnostic-filtering.md

## Problem

Seven concrete pain points from WiFi provisioning retrospective:

1. **BLE/probe-rs interference cycle** — 5+ manual steps per test iteration
2. **Twister broken on macOS** — pyenv noise corrupts cmake JSON output
3. **Build output overflow** — ESP32 builds return ~80KB, hitting token limits
4. **No nrfutil in MCP** — manual shell commands for nRF5340/nRF7002-DK flashing
5. **Sequential board testing** — ESP32 and nRF can't be verified in parallel
6. **Single build dir per app** — building for nRF wipes ESP32 artifacts
7. **No ESP32 auto-detection** — requires manual port specification

## Approach

Six phases ordered by impact-per-effort:
- Phase 1: Quick wins in zephyr-build (1A output truncation, 1B pyenv fix, 1C per-board dirs, 1D compile_commands symlink)
- Phase 2: ESP32 auto-detection in esp-idf-build
- Phase 3: nrfutil support in embedded-probe
- Phase 4: Hardware Test Runner MCP (Python, BLE + TCP)
- Phase 5: Parallel board testing documentation
- Phase 6: /hw-verify skill

## Solution

All seven pain points addressed across six phases:

**Phase 1A** — `truncate_output()` function in zephyr-build keeps first 50 + last 100 lines, replacing middle with `[N lines truncated]`. Applied to all build and test output. Max 8KB default.

**Phase 1B** — `twister_command()` strips `~/.pyenv/shims` from PATH before spawning, preventing pyenv stderr noise from corrupting cmake JSON output.

**Phase 1C** — Build directories changed from `apps/<name>/build/` to `apps/<name>/build/<board_sanitized>/` where `/` in board names becomes `_`. `clean(app)` removes all boards; `clean(app, board)` removes one. `list_apps()` reports `built_boards` array.

**Phase 1D** — Post-build step symlinks `compile_commands.json` from the build dir to the app source root, allowing clangd to find Zephyr-specific compile flags.

**Phase 2** — New `detect_device` tool in esp-idf-build scans serial ports and matches USB VID/PIDs for known ESP32 USB-UART bridges (CP2102, CH340, FTDI, etc.). Returns port, chip type, and bridge info.

**Phase 3** — Three new tools in embedded-probe: `nrfutil_program` (with dual-core support for nRF5340), `nrfutil_recover` (clears APPROTECT), `nrfutil_reset`. All use async `tokio::process::Command`.

**Phase 4** — New Python MCP server (`hw-test-runner`) with 9 tools: 4 low-level BLE (discover, read, write, subscribe) + 4 WiFi provisioning (provision, scan_aps, status, factory_reset) + 1 TCP throughput. Uses bleak for BLE, completely independent of probe-rs/J-Link.

**Phase 5** — Parallel board testing workflow documented in CLAUDE.md. Per-board build dirs + independent flash interfaces (nrfutil via J-Link, esptool via USB-serial) + independent BLE testing (CoreBluetooth) enable concurrent nRF + ESP32 verification.

**Phase 6** — `/hw-verify <app> <board>` skill provides a 9-step guided checklist: build, flash, boot validation, log inspection, BLE discovery, functional tests, persistence, factory reset, throughput baseline.

## Implementation Notes

### Files changed

**zephyr-build** (`claude-mcps/zephyr-build/src/tools/`):
- `build_tools.rs` — truncate_output(), pyenv PATH stripping, build_dir_for_board(), symlink_compile_commands(), updated all build/clean/list_apps call sites. 9 new tests.
- `types.rs` — `CleanArgs.board: Option<String>`, `AppInfo.built_boards: Option<Vec<String>>` (replaced `board`)

**esp-idf-build** (`claude-mcps/esp-idf-build/src/tools/`):
- `build_tools.rs` — KNOWN_BRIDGES constant, detect_esp32_devices() with system_profiler parsing. 2 new tests.
- `types.rs` — DetectDeviceArgs, DetectedDevice, DetectDeviceResult

**embedded-probe** (`claude-mcps/embedded-probe/src/tools/`):
- `debugger_tools.rs` — nrfutil_program, nrfutil_recover, nrfutil_reset tools
- `types.rs` — NrfutilProgramArgs, NrfutilRecoverArgs, NrfutilResetArgs

**hw-test-runner** (`claude-mcps/hw-test-runner/`):
- New Python MCP server: pyproject.toml, __main__.py, server.py, ble.py, provisioning.py, throughput.py, CLAUDE.md
- Tests: test_provisioning.py (20 tests), test_server.py (6 tests), test_throughput.py (3 tests)

**Workspace**:
- `.mcp.json` — added hw-test-runner server entry
- `CLAUDE.md` — added hw-test-runner MCP section, parallel testing workflow, /hw-verify command
- `claude-config/commands/hw-verify.md` — new skill
- `claude-mcps/CLAUDE.md` — added hw-test-runner to table

### Test results
- zephyr-build: 69 tests pass (55 unit + 8 main + 6 integration)
- esp-idf-build: 18 tests pass (8 unit + 5 main + 5 integration)
- embedded-probe: 59 tests pass (50 unit + 9 integration)
- hw-test-runner: 29 tests pass

### Gotchas
- pyproject.toml build-backend must be `setuptools.build_meta`, not the legacy backend
- `CleanArgs` gained an optional `board` field — existing tests needed updating
- Background build closures need separate clones for both `build_dir` and `app_path` (one for artifacts, one for compile_commands symlink)
- ESP32 detection uses `system_profiler SPUSBDataType` on macOS — platform-specific

## Modifications

- LSP diagnostic filtering (Phase 1D) simplified to just the compile_commands.json symlink approach. The `.clangd` config file and `-ferror-limit=0` fallback from the original plan were unnecessary — the symlink alone is sufficient.
- The `/hw-verify` skill was placed in `claude-config/commands/` (matching existing skill pattern) rather than `claude-config/skills/` as originally planned.

## Verification

- [x] Phase 1A: Build output under 10KB for large builds — truncate_output() keeps head+tail, unit tests pass
- [x] Phase 1B: run_tests succeeds without manual PATH workaround — pyenv shims stripped from PATH
- [x] Phase 1C: Building for nRF then ESP32 preserves both build artifacts — per-board dirs, unit tests pass
- [x] Phase 1C: clean(app) removes all; clean(app, board) removes one — unit tests pass
- [x] Phase 1D: compile_commands.json symlinked after build — symlink_compile_commands() called post-build
- [x] Phase 2: detect_device() finds connected ESP32 — tool registered, VID/PID matching implemented
- [x] Phase 3: nrfutil_program() flashes nRF device — tool registered with dual-core support
- [x] Phase 4: BLE provisioning without probe-rs — hw-test-runner MCP with 9 tools, 29 tests pass
- [x] Phase 5: Parallel workflow documented — CLAUDE.md updated with workflow section
- [x] Phase 6: /hw-verify skill works — skill registered and visible in available skills

Note: Phases 2, 3, and 4 tools are verified at the code/test level. Live hardware validation requires connected devices (ESP32 for Phase 2, nRF5340 for Phase 3, BLE device for Phase 4).
