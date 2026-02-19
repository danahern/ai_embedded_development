# Retrospective Quick Wins

Status: Complete
Created: 2026-02-18

## Problem
The retrospective analysis identified 5 high-impact, low-effort improvements that should be tackled immediately. These address knowledge quality, developer efficiency, context window optimization, data consistency, and test coverage gaps.

## Approach

Work through all 5 items sequentially, verifying each before moving on:

1. **Fix `regenerate_gotchas()` validation filter** — Add `status == "validated"` check to the filter in `handler.rs:692`. Currently only checks `severity == "critical" && !deprecated`, letting unvetted items reach Tier 1.

2. **Trim CLAUDE.md to ~8 KB** — Remove MCP Servers tool reference tables (5.2 KB, duplicates server descriptions), Common Boards table (use `knowledge.board_info()` instead), trim Typical Workflows to 2-3 examples, condense Plans/Permissions/Workspace sections.

3. **Backfill knowledge metadata** — All 98 items have `status:` field (earlier "8 missing" report was stale). Actual gap: 76 of 98 items are `unvalidated`. No field backfill needed — this item is already resolved.

4. **Add tests to untested MCP servers** — elf-analysis (has 10 inline unit tests but 0 integration tests), esp-idf-build (has 5 integration tests but minimal), linux-build (has 2 inline tests only). Add config/handler creation integration tests following knowledge-server patterns.

5. **Create `/bft` build-flash-test skill** — Single command that chains: build → flash → validate_boot → rtt_read → report. Board-aware (nRF uses .hex/nrfutil, ESP32 uses esptool).

## Solution

All 5 items completed (item 3 was already resolved):

1. **`regenerate_gotchas()` fixed** — Added `i.status == "validated"` to filter. Also added `unvalidated_critical_count` and `unvalidated_critical` array to output so users see what's excluded. Knowledge server builds and all 16 tests pass.

2. **CLAUDE.md trimmed** — 18.6 KB → 8.0 KB (57% reduction, 307 → 118 lines). Removed: MCP Servers tool tables (5.2 KB), Common Boards table, Permission Rules section, 4 workflow examples. Kept: Collaboration Style, Key Gotchas, MCP-First Policy, Knowledge tiers, Testing, Key Commands. MCP server list is now a compact 1-liner per server referencing each server's own CLAUDE.md for details.

3. **Knowledge metadata** — No action needed. All 98 items have `status:` field. 22 validated, 76 unvalidated. The earlier "8 missing" report was from before a backfill that already happened.

4. **MCP server tests added** — Integration tests added to elf-analysis (7 new tests) and linux-build (10 new tests). All pass:
   - elf-analysis: 23 total (11 unit + 5 main + 7 integration)
   - linux-build: 39 total (25 unit + 4 main + 10 integration)
   - esp-idf-build: 18 total (8 unit + 5 main + 5 integration) — already had more tests than initially reported

5. **`/bft` skill created** — `.claude/commands/bft.md` with board-aware logic for nRF (nrfutil + RTT), ESP32 (esptool + monitor), Linux (SSH deploy), and QEMU (build + run_tests). Includes failure recovery suggestions and compact summary output.

## Implementation Notes

Files changed:
- `claude-mcps/knowledge-server/src/tools/handler.rs` — Added validated filter + unvalidated count to output
- `CLAUDE.md` — Trimmed from 18.6 KB to 8.0 KB
- `claude-mcps/elf-analysis/tests/integration_tests.rs` — New file, 7 tests
- `claude-mcps/linux-build/tests/integration_tests.rs` — New file, 10 tests
- `.claude/commands/bft.md` — New skill
- `plans/retrospective-actions.md` — This plan

Surprises:
- linux-build already had 25 inline unit tests in `tools/linux_build_tools.rs` — the "0 tests" from the retrospective only counted `tests/` directory files, missing inline `#[cfg(test)]` modules
- esp-idf-build had 8 inline unit tests in `build_tools.rs` plus 5 integration tests — also more than initially reported
- Knowledge metadata backfill was already done — no items missing `status:` field
