# Embedded Development Workspace

## Collaboration Style

**Ask questions and propose approaches before diving into implementation.**

- Propose an approach first when multiple paths exist. Surface tradeoffs.
- If you hit something unexpected, explain what you found and ask which direction to go.
- When a task touches multiple subsystems, outline the pieces and confirm scope before starting.

## Key Gotchas

Hard-won lessons (Tier 1 — always loaded). Full details in individual `learnings/` files.

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
- **Twister SDK env vars**: MCP subprocesses don't inherit shell profile env vars. The `run_tests` tool auto-detects the SDK from `~/.cmake/packages/Zephyr-sdk/`. If that fails, set `ZEPHYR_TOOLCHAIN_VARIANT=zephyr` and `ZEPHYR_SDK_INSTALL_DIR` in the MCP launch environment.

## Permission Rules (settings.local.json)

Claude Code tracks tool permissions in `.claude/settings.local.json`. This file is auto-generated when you click "Allow" on tool prompts — you never need to create it manually.

- **Location**: `.claude/settings.local.json` (gitignored, per-machine)
- **Pattern syntax**: `ToolName(prefix:*)` — e.g., `Bash(git *)` allows all git commands
- **Key categories in this workspace**:
  - `Bash(git *)` — git operations
  - `Bash(cargo *)`, `Bash(cd * && cargo *)` — Rust builds and tests
  - `Bash(python3 *)`, `Bash(*/bin/pip *)` — Python tooling
  - `mcp__*` — MCP server tool calls (auto-allowed per server)
- **Maintenance**: Safe to delete the file or prune entries. Permissions are re-added the next time you approve a prompt. If tool prompts become excessive, check that the file exists and hasn't been corrupted.

## Plans

Plans track significant new work. **Required for:** new MCPs, skills, agents, commands, apps, libraries, test tool groups, or changes touching 5+ source files.

### Lifecycle

`Ideation` → `Planned` → `In-Progress` → `Complete`

All plans live in `plans/`. Completed plans stay in place — status in the file header distinguishes active from done. No archive directory.

### Plan template

```markdown
# Feature Name

Status: Planned
Created: 2026-02-14

## Problem
What's broken or missing, and why it matters.

## Approach
High-level strategy and key decisions.

## Solution
What was built — deliverables, APIs, behavior.

## Implementation Notes
Files changed, gotchas, things that surprised you.

## Modifications
What was deferred, descoped, or changed from the original approach.
```

Sections are added as the plan progresses — an Ideation plan may only have Problem and Approach; a Complete plan should have all five.

- **Naming:** descriptive kebab-case, no phase numbers
- **No index file** — `ls plans/` shows all plans; status in header shows what's active
- Plans are git-tracked

### CRITICAL: Plan maintenance rules

**Plans must be kept in sync with reality. Violations create confusion and lost context.**

1. **One plan, one location.** The file in `plans/` is the single source of truth. Session plan files (`.claude/plans/`) are drafts — once approved, copy the full content to `plans/<name>.md` immediately. Never leave a plan only in the session file.
2. **Create the plan file BEFORE starting implementation.** When you begin coding, the plan must already exist in `plans/` with status `In-Progress`.
3. **Never mark Complete until ALL verification steps pass.** If the plan has a Verification section, every item must be confirmed. If tools haven't been live-tested, the plan is not complete.
4. **Update incrementally.** When you discover gotchas, make design decisions, or change approach during implementation — update the plan file right then, not later.

## Project Documentation

The same threshold that requires a plan also determines documentation depth:

- **New MCPs, skills, agents, commands, apps, libraries, test tool groups** — Full three docs + a plan:
  - **`README.md`** — Human-facing: setup, usage, configuration, troubleshooting
  - **`PRD.md`** — Requirements: purpose, design decisions, API surface, constraints
  - **`CLAUDE.md`** — Claude-facing: architecture, tool listings, implementation details
- **Small components** (device_shell, single-file libraries) — **`CLAUDE.md` only** is sufficient

Keep docs current as requirements change or features are added.

## Testing

**Generated code must be unit tested.** Not just happy path — test failure cases too.

- Tests should verify **expected behavior**, not mirror implementation details.
- Cover edge cases: invalid input, missing files, empty data, error conditions.
- If a function can fail, test that it fails correctly.

## Learnings

Three-tier retrieval system — the right knowledge reaches Claude at the right time without bloating context.

| Tier | What | Where | When |
|------|------|-------|------|
| 1 | Critical gotchas (10-15) | `CLAUDE.md` Key Gotchas section | Every session, always in context |
| 2 | Topic rules (5+ files) | `.claude/rules/*.md` | Auto-injected when editing matching files |
| 3 | Full corpus (all learnings) | `learnings/YYYY/*.md` | On-demand via `/recall` |

### Adding learnings

Use `/learn` during a session or `/wrap-up` at session end. Each learning is one file in `learnings/YYYY/YYYY-MM-DD-kebab-slug.md` with YAML frontmatter (`title`, `date`, `author`, `tags`).

### Tag conventions

| Category | Examples |
|----------|----------|
| Chips | `nrf52840`, `nrf54l15`, `esp32`, `esp32s3` |
| Subsystems | `zephyr`, `bluetooth`, `coredump`, `shell`, `dts`, `kconfig` |
| Tools | `probe-rs`, `twister`, `west`, `size-report`, `rtt` |
| Concepts | `flashing`, `testing`, `build-system`, `memory`, `overlay` |
| Platforms | `macos`, `linux`, `qemu` |

### Session workflow

**Run `/start` at the beginning of a session** to bootstrap context (refreshes recent learnings, shows recent activity, checks hardware).

**Run `/wrap-up` at the end of a session** to capture learnings and commit work.

After debugging surprises or non-obvious behavior, run `/learn` to capture findings immediately.

## CRITICAL: MCP-First Policy

**ALWAYS use MCP tools for operations they support. NEVER shell out to CLI equivalents (addr2line, west, idf.py, nrfjprog, etc.).**

If an MCP tool fails:
1. **STOP and tell the user.** Explain which tool failed and why.
2. **Suggest the fix** — e.g., rebuild the MCP server and restart.
3. **Do NOT silently fall back** to raw CLI commands.

## MCP Servers

### zephyr-build (Building & Testing)
- `list_apps()`, `list_boards(filter="nrf")`, `build(app, board, pristine=true)`, `build(app, board, background=true)`, `build_all(board, pristine=true)`, `build_status(build_id)`, `clean(app)`
- `list_templates()` — discover available app templates before creating
- `create_app(name, template?, board?, libraries?, description?)` — scaffold a new app from template
- `run_tests(board, path?, filter?, background?)`, `test_status(test_id)`, `test_results(test_id?, results_dir?)`

### elf-analysis (Size Analysis)
- `analyze_size(elf_path, target?, depth?, workspace_path?)` — ROM/RAM breakdown with per-file tree
- `compare_sizes(elf_path_a, elf_path_b, workspace_path?)` — diff two ELFs, show top increases/decreases
- `top_consumers(elf_path, target, limit?, level?, workspace_path?)` — biggest files/symbols sorted by size

### esp-idf-build (ESP-IDF)
- `list_projects()`, `list_targets()`, `set_target(project, target)`, `build(project)`, `flash(project, port)`, `monitor(project, port, duration_seconds)`, `clean(project)`

### embedded-probe (Debug & Flash)
- `list_probes()`, `connect(probe_selector, target_chip)`, `flash_program(session_id, file_path)`, `validate_boot(session_id, file_path, success_pattern)`, `rtt_attach(session_id)`, `rtt_read(session_id)`, `reset(session_id)`, `resolve_symbol(address, elf_path)`, `stack_trace(session_id, elf_path)`, `analyze_coredump(log_text, elf_path)`

### knowledge (Knowledge Management)
- `capture(title, body, category?, severity?, boards?, chips?, tools?, subsystems?, file_patterns?, tags?, author?)` — create knowledge item
- `search(query, tags?, chips?, category?, limit?)` — full-text search with FTS5
- `for_context(files, board?)` — knowledge relevant to current files + build target
- `deprecate(id, superseded_by?)`, `validate(id, validated_by)` — lifecycle management
- `recent(days?)`, `stale(days?)`, `list_tags(prefix?)` — discovery and maintenance
- `board_info(board)`, `for_chip(chip)`, `for_board(board)`, `list_boards(vendor?)` — hardware-aware retrieval
- `regenerate_rules(dry_run?)`, `regenerate_gotchas(dry_run?)` — auto-generate rules and gotchas

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
1. `zephyr-build.run_tests(board="qemu_cortex_m3")` — run all lib tests
2. `zephyr-build.run_tests(path="lib/crash_log", board="qemu_cortex_m3")` — filtered
3. `zephyr-build.test_results(test_id=...)` — get structured pass/fail details

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
| `claude-mcps/` | MCP servers (embedded-probe, zephyr-build, elf-analysis, esp-idf-build, saleae-logic, knowledge-server) | Submodule |
| `knowledge/` | Knowledge items (`items/*.yml`) and board profiles (`boards/*.yml`) | Tracked |
| `zephyr-apps/` | Zephyr apps, shared libraries, tests | Submodule |
| `esp-dev-kits/` | ESP-IDF example projects | Cloned |
| `test-tools/` | Python BLE/power testing utilities | Tracked |
| `zephyr/`, `bootloader/`, `modules/`, `tools/` | West-managed dependencies | Gitignored |

## Key Commands

- `/start` — Bootstrap a session (refresh recent learnings, check hardware, show recent changes)
- `/wrap-up` — End a session (review changes, capture learnings, commit)
- `/learn` — Capture a learning from the current session with metadata and tags
- `/recall` — Search the learnings corpus by topic, tag, or keyword
- `/embedded` — Full embedded development guidelines (memory, style, Zephyr patterns)
