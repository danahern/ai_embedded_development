# Embedded Development Workspace

## Collaboration Style
- Act like a senior engineer, evalute requests, if there is a better way propose it.  This is a collaborative project.

**Ask questions and propose approaches before diving into implementation.**

- Propose an approach first when multiple paths exist. Surface tradeoffs.
- If you hit something unexpected, explain what you found and ask which direction to go.
- When a task touches multiple subsystems, outline the pieces and confirm scope before starting.

## Key Gotchas

Hard-won lessons (Tier 1 — always loaded). Full details via `knowledge.search()` or `/recall`.

### Zephyr / Build System
- **nRF54L15**: Use `.hex` not `.elf` for flashing. `flash_program` works; `run_firmware` (erase+program) fails. Use `connect_under_reset=true` to recover stuck states.
- **native_sim**: Linux-only. Use `qemu_cortex_m3` for unit tests on macOS.
- **qemu_cortex_m3 has no flash driver**: lm3s6965 — NVS/Settings cannot work. Use `mps2/an385` instead. Use `platform_allow` in testcase.yaml (not just `integration_platforms`).
- **Flash backend needs real hardware**: `CONFIG_DEBUG_COREDUMP_BACKEND_FLASH_PARTITION` requires `FLASH_HAS_DRIVER_ENABLED`. Won't build on QEMU — use `build_only: true` with `platform_allow`.
- **QEMU + core template**: `create_app` core template includes crash_log/device_shell overlays that require RTT and flash — unavailable on QEMU. Remove `OVERLAY_CONFIG` lines for QEMU-only apps.
- **Shell naming**: Zephyr has a built-in `device` shell command. Pick unique names for custom commands.
- **Log buffer drops**: Boot-time coredump auto-report drops messages if `CONFIG_LOG_BUFFER_SIZE` is too small (default 1024). Set to 4096+.
- **RTT buffer conflict**: `LOG_BACKEND_RTT` and `SHELL_BACKEND_RTT` both default to buffer 0. Set `SHELL_BACKEND_RTT_BUFFER=1`.
- **RTT chunks**: Output arrives in ~1KB chunks. Concatenate all reads until `#CD:END#` before passing to `analyze_coredump`.
- **module.yml paths**: Relative to module root (parent of `zephyr/`), not relative to the yml file.
- **Board qualifiers**: `/` in CMake (`nrf52840dk/nrf52840`), `_` in overlay filenames (`nrf52840dk_nrf52840.overlay`).
- **coredump_cmd return**: `COREDUMP_CMD_COPY_STORED_DUMP` returns positive byte count on success, not 0.
- **Build dirs are per-board**: Each app builds to `apps/<name>/build/<board_sanitized>/`. Multiple boards coexist.
- **Twister SDK env vars**: MCP subprocesses don't inherit shell profile env vars. Auto-detects from `~/.cmake/packages/Zephyr-sdk/`. If that fails, set `ZEPHYR_TOOLCHAIN_VARIANT` and `ZEPHYR_SDK_INSTALL_DIR`.
- **Zephyr CI container**: `ghcr.io/zephyrproject-rtos/ci` registers SDK for `user`, but GH Actions runs as root. Run `/opt/toolchains/zephyr-sdk-*/setup.sh -c` first.
- **Gitignore negation**: `.claude/` (trailing slash) makes git skip the entire directory. Use `.claude/*` with `!.claude/rules/`.

### nRF7002-DK / nRF5340
- **nRF7002-DK flash**: probe-rs fails on nRF5340 (APPROTECT). Use `nrfutil device recover` then `nrfutil device program --firmware <hex> --core Application --traits jlink`.
- **nRF7002-DK dual-core BLE**: Net core needs `hci_ipc` firmware. Without it, BLE init fails with HCI error -11 (EAGAIN).
- **nRF7002 WiFi Kconfig**: Use `CONFIG_WIFI_NRF70=y`, not `CONFIG_WIFI_NRF700X`. Also `CONFIG_WIFI_NM_WPA_SUPPLICANT=y`, not `CONFIG_WPA_SUPP`. Fetch blobs first: `west blobs fetch nrf_wifi`.

### ESP32
- **ESP32 WiFi power management**: Modem sleep blocks incoming TCP/ping. Call `esp_wifi_set_ps(WIFI_PS_NONE)` after `esp_wifi_start()`.
- **ESP32 FreeRTOS stack sizes**: `StackType_t` is `uint8_t` on Xtensa — `xTaskCreate` stack_depth is in bytes, not words. Use 4096+ for WiFi tasks.
- **BLE GATT callbacks**: Must not block. Defer WiFi connect, NVS writes, factory reset to `k_work`/work queue. Copy data to static buffer before submitting.

### STM32MP1
- **M4 has no persistent flash**: Firmware loaded to RETRAM/MCUSRAM via OpenOCD `load_image`. Lost on power cycle. Production uses remoteproc.
- **Use remoteproc for M4 firmware**: Copy ELF to `/lib/firmware/`, echo to `/sys/class/remoteproc/remoteproc0/`. OpenOCD is for bare-metal debug only.
- **OpenOCD config**: Must disable A7 GDB ports and set M4 as active target for M4-only debugging.
- **USB gadget macOS**: No RNDIS support on macOS. Must use pure CDC-ECM. Build kernel with `CONFIG_USB_ETH_RNDIS=n`.
- **DWC2 composite USB fails**: Limited FIFOs (952 entries). CDC-ECM + FunctionFS (ADB) exceeds them. Use ADB-only gadget.
- **CDC-ECM IP conflict**: Bring down usb0 (RNDIS, 192.168.7.2) before configuring ECM, or kernel routes via wrong interface.
- **Dropbear SSH on macOS**: v2018.76 only supports ssh-rsa. Add `HostKeyAlgorithms +ssh-rsa` to `~/.ssh/config`.
- **Buildroot glibc mismatch**: Cross-compiled binaries may need `-static` if SD card has older glibc.
- **Serial FD leak**: Killed serial scripts leak FDs to parent process. Replug USB to recover.

### Yocto / Docker
- **Yocto case-sensitive FS**: macOS is case-insensitive. Use Docker named volume (not bind mount) for build dir.
- **Yocto OOM on Apple Silicon**: Docker defaults ~8GB RAM. Set `BB_NUMBER_THREADS=4` and `PARALLEL_MAKE="-j 4"` to avoid OOM on GCC build.
- **Alif E7 BSP vars**: With `DISTRO="poky"` (not `apss-tiny`), must set `ALIF_KERNEL_TREE`, `TFA_TREE`, etc. manually in `local.conf`.

### Operational
- **MCP server testing**: MCP servers MUST have unit tests for core logic (ID generation, parsing, encoding). Silent bugs are destructive.

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
