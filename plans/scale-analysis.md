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
