Category 1: Breaks Immediately (Blockers for 5+ engineers)

  1. Hardcoded paths in .mcp.json
  "command": "/Users/danahern/code/claude/work/claude-mcps/embedded-probe/target/release/embedded-probe"
  Every engineer needs different absolute paths. Need either relative paths, or a setup.sh that generates .mcp.json from a template with $PWD substitution.

  2. No CI/CD — zero automated quality gates
  Right now, nothing stops a broken build from landing. At 50 engineers, someone will push code that breaks every other app daily. Need:
  - Build verification on PR (at minimum build_all for each target board)
  - Twister test runs on QEMU (works without hardware, runs on any CI runner)
  - Kconfig/DTS validation (catches misconfigurations before flash)

  3. No testing MCP server
  Twister is the Zephyr test runner, but it's invoked via raw CLI:
  python3 zephyr/scripts/twister -T zephyr-apps/lib -p qemu_cortex_m3
  Need a zephyr-test MCP (or add tools to zephyr-build) with:
  - run_tests(path, board, filter) — run twister with result parsing
  - test_status(test_id) — background test polling
  - test_results(test_id) — structured pass/fail/skip with failure details

  4. No project scaffolding
  Creating a new Zephyr app today means copying crash_debug/, editing CMakeLists.txt, prj.conf, etc. At 25 projects, you need:
  - create_app(name, board, libraries=[]) — generates app skeleton with correct CMake, Kconfig, overlays
  - Templates for common patterns (BLE peripheral, sensor app, shell-only, etc.)

  ---
  Category 2: Painful at 10+ Engineers (Should Fix Early)

  5. Learnings are local and manual
  learnings/*.md captures tribal knowledge well for 1 person. At 50:
  - Merge conflicts when multiple people add learnings in the same session
  - No structure — how does engineer #47 find the gotcha about nRF54L15 RRAM?
  - No validation — stale learnings never get pruned

  Needs: Structured learnings (tagged by chip/subsystem/tool), searchable, with a /learn skill that appends atomically with metadata (date, author, tags).

  6. No memory/resource analysis
  Embedded projects live and die by ROM/RAM budgets. Missing:
  - analyze_elf(elf_path) — parse ELF sections, report flash/RAM usage by module
  - compare_sizes(elf_a, elf_b) — diff two builds to show what grew
  - Automated size tracking per-PR (catch bloat before it ships)

  This could be a new MCP server or added to zephyr-build.

  7. Hardware contention and allocation
  One J-Link today. At 50 engineers:
  - Each engineer needs their own dev kit (or shared hardware farm with remote access)
  - Need to know which boards are available, who's using what probe
  - list_probes() only sees locally-connected probes — no network awareness

  8. No configuration management tools
  Engineers will constantly misconfigure prj.conf and overlays. Need:
  - validate_config(app, board) — check for known conflicts (RTT buffer collisions, missing dependencies)
  - show_config(app, board) — dump resolved Kconfig for an app+board combo
  - Could live in zephyr-build as menuconfig alternative

  ---
  Category 3: Important for 25+ Projects

  9. Multi-project build orchestration
  build_all exists but is basic. At 25 projects:
  - Build matrix: 25 apps x N boards = hundreds of combinations
  - Need dependency-aware builds (only rebuild what changed)
  - Build caching across engineers (ccache, or shared sysroot)
  - build_matrix(apps=[], boards=[]) with parallel execution and summary

  10. No app/library dependency graph
  When crash_log changes, which apps need rebuilding? Today: you guess. Need:
  - dependency_graph() — show which apps use which libraries
  - impact_analysis(changed_files) — given a set of changed files, what needs rebuilding/retesting?

  11. No firmware versioning or release management
  25 projects shipping firmware = you need to know what's running on each device:
  - Version strings baked into firmware (build metadata)
  - board info shell command already exists but needs version
  - Release tagging, changelog generation
  - Binary artifact storage (not just build-and-throw-away)

  12. No BLE/protocol testing automation
  test-tools/ has bleak for BLE, but no MCP integration. At scale:
  - ble_scan() — discover devices
  - ble_connect(address) — connect and enumerate services
  - ble_read/write(characteristic) — functional testing
  - Integration with Saleae for protocol-level validation

  ---
  Category 4: Nice-to-Have / Long-term

  ┌──────────────────────────┬──────────────────────────────────────────────────────────────┬──────────────────────────────┐
  │           Gap            │                         Description                          │           Priority           │
  ├──────────────────────────┼──────────────────────────────────────────────────────────────┼──────────────────────────────┤
  │ Security tooling         │ Firmware signing, secure boot config                         │ When shipping products       │
  ├──────────────────────────┼──────────────────────────────────────────────────────────────┼──────────────────────────────┤
  │ Power profiling MCP      │ Current measurement integration (PPK2, Otii)                 │ When optimizing battery life │
  ├──────────────────────────┼──────────────────────────────────────────────────────────────┼──────────────────────────────┤
  │ OTA update testing       │ Flash + verify + rollback workflows                          │ When doing OTA               │
  ├──────────────────────────┼──────────────────────────────────────────────────────────────┼──────────────────────────────┤
  │ Documentation generation │ Auto-generate API docs from headers                          │ When library count > 10      │
  ├──────────────────────────┼──────────────────────────────────────────────────────────────┼──────────────────────────────┤
  │ Remote debug             │ Network-accessible probe sharing (probe-rs has some support) │ When hardware is shared      │
  └──────────────────────────┴──────────────────────────────────────────────────────────────┴──────────────────────────────┘

  ---
  Recommended Build Order

  If I were prioritizing for onboarding 50 engineers:

  ┌─────────┬──────────────────────────────────────────────────────┬─────────────────────────────────────┬────────┐
  │  Phase  │                         What                         │                 Why                 │ Effort │
  ├─────────┼──────────────────────────────────────────────────────┼─────────────────────────────────────┼────────┤
  │ Phase 0 │ Fix .mcp.json portability, add setup.sh improvements │ Can't onboard anyone without this   │ Small  │
  ├─────────┼──────────────────────────────────────────────────────┼─────────────────────────────────────┼────────┤
  │ Phase 1 │ Add run_tests / test_results to zephyr-build MCP     │ Engineers need to verify their work │ Medium │
  ├─────────┼──────────────────────────────────────────────────────┼─────────────────────────────────────┼────────┤
  │ Phase 2 │ GitHub Actions CI (build_all + twister on QEMU)      │ Quality gates before merge          │ Medium │
  ├─────────┼──────────────────────────────────────────────────────┼─────────────────────────────────────┼────────┤
  │ Phase 3 │ create_app scaffolding skill/tool                    │ Consistent project creation         │ Small  │
  ├─────────┼──────────────────────────────────────────────────────┼─────────────────────────────────────┼────────┤
  │ Phase 4 │ analyze_elf size analysis tool                       │ Catch resource regressions          │ Medium │
  ├─────────┼──────────────────────────────────────────────────────┼─────────────────────────────────────┼────────┤
  │ Phase 5 │ Structured learnings with search                     │ Scale tribal knowledge              │ Small  │
  ├─────────┼──────────────────────────────────────────────────────┼─────────────────────────────────────┼────────┤
  │ Phase 6 │ Build matrix + dependency tracking                   │ Efficient CI for 25 projects        │ Large  │
  ├─────────┼──────────────────────────────────────────────────────┼─────────────────────────────────────┼────────┤
  │ Phase 7 │ BLE testing MCP server                               │ End-to-end validation               │ Large  │
  └─────────┴──────────────────────────────────────────────────────┴─────────────────────────────────────┴────────┘

  ---
  The Biggest Single Gap

  Testing. You have 66 tools for building, flashing, and debugging — but zero tools for verifying correctness at scale. A single engineer can manually flash and
  check. 50 engineers need:

  1. MCP tools to run and parse test results
  2. CI that runs on every PR
  3. Hardware-in-the-loop test infrastructure (or at least QEMU coverage)

  That's where I'd focus first. Want me to dig deeper into any of these areas, or start designing one of the solutions?