# Scale Analysis: 1 Engineer → 50 Engineers, 25 Projects

Date: 2026-02-14

## Current State

| Layer | Current State | Tools |
|-------|--------------|-------|
| **Build** | Zephyr + ESP-IDF MCP servers | 14 tools |
| **Flash/Debug** | embedded-probe (probe-rs + vendor CLI) | 31 tools |
| **Signal Analysis** | saleae-logic | 21 tools |
| **Skills** | `/start`, `/wrap-up`, `/embedded` | 3 skills |
| **Knowledge** | `learnings/*.md`, CLAUDE.md hierarchy | Manual |
| **Testing** | Twister (manual CLI) | 0 tools |
| **CI/CD** | None | 0 |
| **Onboarding** | `setup.sh` + `.mcp.json` | Semi-manual |

**Total: 66 MCP tools, 3 skills, 0 test automation.**

---

## Priority Categories

### Category 1: Breaks Immediately (Blockers for 5+ engineers)

1. **Hardcoded paths in `.mcp.json`** — Every engineer needs different absolute paths. Need `setup.sh` to generate `.mcp.json` from template with `$PWD` substitution.

2. **No CI/CD — zero automated quality gates** — Nothing stops broken builds from landing. Need build verification on PR, twister on QEMU, Kconfig validation.

3. **No testing MCP server** — Twister invoked via raw CLI only. Need `run_tests`, `test_status`, `test_results` tools with structured output.

4. **No project scaffolding** — Creating a new app means copy-paste. Need `create_app(name, board, libraries=[])` with templates.

### Category 2: Painful at 10+ Engineers

5. **Learnings are local and manual** — No structure, no search, merge conflicts. Need tagged/searchable learnings with `/learn` skill.

6. **No memory/resource analysis** — No ROM/RAM tracking. Need `analyze_elf`, `compare_sizes` tools.

7. **Hardware contention** — One J-Link today. Each engineer needs their own dev kit or shared hardware farm.

8. **No configuration management tools** — Need `validate_config`, `show_config` tools.

### Category 3: Important for 25+ Projects

9. **Multi-project build orchestration** — Build matrix: 25 apps x N boards. Need dependency-aware builds.

10. **No app/library dependency graph** — Need `dependency_graph()`, `impact_analysis(changed_files)`.

11. **No firmware versioning** — Need version strings, release tagging, binary artifact storage.

12. **No BLE/protocol testing automation** — `test-tools/` has bleak but no MCP integration.

### Category 4: Long-term

- Security tooling (firmware signing, secure boot)
- Power profiling MCP (PPK2, Otii integration)
- OTA update testing
- Documentation generation
- Remote debug (network-accessible probe sharing)

---

## Board Overlay Scaling Problem

Current: 2 libs x 3 boards = 6 overlay files.
At scale: 10 libs x 15 boards = **150 DTS overlay files** with no sharing mechanism.

Solution: Shared `lib/boards/` directory with library-specific deltas.

---

## Build System Scaling

- **Kconfig overlay boilerplate** grows linearly with library count per app
- **Library dependencies** are implicit (prj.conf enables, nothing declares deps)
- **Test discovery** has no metadata registry at scale

Solutions: App manifest files (`manifest.yml`), overlay aggregation, test registry.

---

## Recommended Build Order

| Plan | What | Status |
|------|------|--------|
| Testing MCP | Testing MCP tools (run_tests, test_results) | Complete |
| CI/CD | GitHub Actions: build_all + twister | Planned |
| Onboarding | Portable .mcp.json, quickstart, dep validation | Complete |
| Scaffolding | create_app tool + manifests | Complete |
| ELF analysis | ELF size analysis tool | Ideation |
| Template evolution | Pattern detection + template suggestions | Ideation |
| Build matrix | Build matrix + dependency tracking | Ideation |
| BLE testing | BLE testing MCP server | Ideation |





# Wifi provisioning retrospective

  ---
  Retrospective: WiFi Provisioning Project

  Project Scope

  - ~2,250 lines of code across firmware library, app, unit tests, and Python tools
  - 14 bugs found and fixed during hardware verification
  - 17 knowledge items captured
  - 22 unit tests, 3 throughput test modes, 5 BLE tool commands

  ---
  What Worked Well

  1. Plan-first approach. The upfront plan defined a clear architecture (shared library + thin app + test tools), QEMU test strategy, and board-specific concerns.
  Hardware verification went straight down a checklist rather than wandering.

  2. Ralph Loop for scaffolding. Ralph produced 15/15 user stories in a single session — the full library, app, test suite, and Python tools. The code was
  structurally sound: correct Kconfig wiring, proper module registration, clean separation of concerns (BLE/WiFi/credentials/state machine). The architecture held
  up; we never needed to restructure.

  3. MCP tools for hardware debugging. The embedded-probe MCP (connect, RTT attach/read, flash, reset) made the debug loop tight. Read RTT, see error, fix code,
  rebuild, flash, re-read — all without leaving the conversation. The zephyr-build MCP kept builds one tool call away.

  4. Knowledge capture during debugging. Capturing learnings as we went (17 items) means the next BLE+WiFi project won't hit the same WPA supplicant stack overflow
  or Settings return value bug. The three-tier retrieval system (CLAUDE.md gotchas, auto-injected rules, searchable corpus) is genuinely useful.

  5. Incremental hardware verification. Testing one feature at a time (BLE connect → WiFi scan → provision → persist → factory reset → throughput) isolated failures
  cleanly. Each step had a clear pass/fail.

  ---
  What Didn't Work

  1. Ralph Loop produced code that looks correct but fails on hardware. 14 bugs, zero of which were caught by QEMU tests. The fundamental problem: Ralph can't test
  BLE/WiFi interactions, stack sizing, or timing. The code compiled and passed unit tests but had:
  - Blocking calls in BLE callbacks (3 bugs)
  - Wrong return values from Settings callbacks
  - Stack sizes too small for WPA supplicant
  - Race conditions with async WiFi connect

  Takeaway: Ralph is a scaffolding tool, not a quality gate. Budget equal time for hardware verification.

  2. probe-rs / BLE interference loop. Every BLE operation required disconnecting probe-rs, doing BLE work, reconnecting probe-rs for RTT. This ate significant time
  and broke flow. The cycle was: disconnect probe → reset device → BLE operation → connect probe → attach RTT → read logs.

  3. Twister / pyenv / MCP subprocess environment. Three separate issues compounded:
  - pyenv noise breaks twister's JSON parsing
  - MCP subprocesses don't inherit shell profile env vars
  - Missing Python packages (colorama, pyyaml, jsonschema, natsort, junitparser)

  Running unit tests should be one tool call. Instead it was 20 minutes of dependency debugging. The zephyr-build MCP's run_tests tool is essentially broken on macOS
   with pyenv.

  4. BLE provisioning notification timing. The CONNECTED status notification often arrives after the BLE client has already timed out and unsubscribed. We worked
  around it (longer timeout, check-after-timeout) but never truly fixed it. The firmware-side fix would be to delay BLE disconnect until after sending the final
  status notification.

  5. No ESP32 hardware validation. Build-only verification is better than nothing, but the RTT Kconfig warnings show the ESP32 board overlay needs a UART logging
  backend. If we'd flashed, we'd have found more board-specific issues.

  ---
  Tools We Need

  1. Twister MCP fix for pyenv. The run_tests tool should strip pyenv shims from PATH or set PYENV_VERSION before invoking twister. This is the single highest-impact
   fix — unit tests should be one click.

  2. nrfutil MCP integration. We're shelling out to nrfutil device program and nrfutil device reset because embedded-probe's flash_program/run_firmware fail on
  nRF5340. Either fix probe-rs nRF5340 support or add nrfutil commands to the MCP.

  3. BLE test tool as MCP. The manual cycle of "disconnect probe, run Python BLE tool, reconnect probe" is painful. An MCP tool that manages probe-rs lifecycle
  around BLE operations (auto-disconnect before, auto-reconnect after) would save significant time.

  4. Build output truncation. The zephyr-build MCP returns full compiler output (~80KB for ESP32), hitting token limits. It should return only the summary (memory
  usage, warnings, errors) by default with an option for full output.

  5. Integration test harness for BLE+WiFi. The gap between "22 QEMU unit tests pass" and "14 hardware bugs found" is unacceptable for a mature workflow. We need
  either:
  - A hardware-in-the-loop test script that automates the probe-rs + BLE + WiFi verification sequence
  - Or better mock/simulation testing that catches stack sizing and callback threading issues

  ---
  Efficiency Improvements

  1. Pre-flight stack analysis. 4 of 14 bugs were stack overflows. A static analysis pass (or even a checklist: "does any thread stack hold a buffer > 1KB?") before
  flashing would catch these.

  2. Board overlay templates. The ESP32 needs UART logging, larger heap, no RTT. The nRF7002-DK needs WPA supplicant, nRF70 driver, net buffers. These should be
  template board overlays in the library, not discovered by trial and error.

  3. Ralph PRD should include hardware gotchas. The PRD had good functional stories but no non-functional requirements like "BLE callbacks must not block" or
  "Settings h_set must return 0". Injecting known gotchas (from the knowledge store) into the PRD would prevent Ralph from generating code with known anti-patterns.

  4. Session state file for multi-session work. This project spanned 3+ sessions (context compactions). Each new session spent time re-reading files, re-establishing
   probe connections, and re-discovering where we left off. A machine-readable session state file (current probe session, device IP, last verified step) would speed
  this up.

  5. Parallel hardware test execution. Build + flash + verify is sequential. If we had two probes (or one probe + one ESP32 via USB), we could test both boards
  simultaneously.

  ---
  By the Numbers

  ┌────────────────────────────┬─────────────────────────┐
  │           Metric           │          Value          │
  ├────────────────────────────┼─────────────────────────┤
  │ Total LoC                  │ 2,250                   │
  ├────────────────────────────┼─────────────────────────┤
  │ Ralph scaffolding bugs     │ 0 (compile/QEMU)        │
  ├────────────────────────────┼─────────────────────────┤
  │ Hardware verification bugs │ 14                      │
  ├────────────────────────────┼─────────────────────────┤
  │ Knowledge items captured   │ 17                      │
  ├────────────────────────────┼─────────────────────────┤
  │ Unit tests                 │ 22/22 pass              │
  ├────────────────────────────┼─────────────────────────┤
  │ Throughput modes verified  │ 3/3                     │
  ├────────────────────────────┼─────────────────────────┤
  │ Board builds verified      │ 2/2 (nRF7002-DK, ESP32) │
  ├────────────────────────────┼─────────────────────────┤
  │ Board flash verified       │ 1/2 (nRF7002-DK only)   │
  ├────────────────────────────┼─────────────────────────┤
  │ Sessions to complete       │ 3+                      │
  └────────────────────────────┴─────────────────────────┘

  Bottom Line

  The plan → Ralph → hardware verification pipeline works. Ralph is excellent at scaffolding — the architecture, module boundaries, and test structure were all
  correct from the start. But hardware verification is where the real debugging happens, and our tooling for that phase (probe management, BLE testing, environment
  setup) needs the most improvement.