# Knowledge Server MCP

Status: Complete
Created: 2026-02-15

## Problem

At thousands of learnings, grep-based search and rules files need supplementing with structured search, hardware-aware retrieval, and staleness analytics. The current three-tier system (CLAUDE.md Key Gotchas + `.claude/rules/` auto-injection + `/recall` grep search) works at small scale but won't scale to large teams or long timeframes.

Key issues: knowledge explosion at scale, flat tag system can't express hardware hierarchy (chip > board > peripheral), plans collide silently with no coordination tools, manual tier promotion and curation doesn't scale.

## Approach

Build an MCP server (Rust, same pattern as existing servers) with:

- **Knowledge Store**: YAML source files + SQLite FTS5 index for fast queries
- **Board Profile Registry**: Hardware hierarchy resolution (board → chip → family → arch)
- **Auto-Generation Engine**: Rules files and CLAUDE.md gotchas generated from knowledge store
- **Enhanced Capture**: `/learn` backed by MCP tools with dedup checking and context pre-fill

Storage is hybrid: YAML files are the git-tracked source of truth, SQLite index is a regenerable cache.

## Phase 1 Scope (Current)

### MCP Tools
- Knowledge CRUD: `capture`, `search`, `for_context`, `deprecate`, `validate`, `recent`, `stale`, `list_tags`
- Board profiles: `board_info`, `for_chip`, `for_board`, `list_boards`
- Auto-generation: `regenerate_rules`, `regenerate_gotchas`

### Data
- Knowledge item YAML schema with structured metadata
- Board profiles for: nrf54l15dk, nrf52840dk, esp32_devkitc, qemu_cortex_m3
- Migration of 24 existing learnings to new format

### Skills
- `/learn` → calls `capture()` with context pre-fill + dedup check
- `/recall` → calls `search()` instead of grep
- `/start` → calls `recent()` for new items since last session

## Implementation Notes

### Files Created
- `claude-mcps/knowledge-server/` — Full Rust MCP server (14 tools)
- `knowledge/items/*.yml` — 24 migrated knowledge items
- `knowledge/boards/*.yml` — 4 board profiles (nrf54l15dk, nrf52840dk, esp32_devkitc, qemu_cortex_m3)
- `scripts/migrate_learnings.py` — Migration script (learnings/*.md → knowledge/items/*.yml)

### Key Decisions
- Used `tokio::sync::Mutex` (not `RwLock`) for SQLite db because `rusqlite::Connection` is `!Sync`
- FTS5 triggers keep the full-text index in sync with the items table automatically
- Board hierarchy resolution uses LIKE queries on JSON arrays (simple, fast enough for <1000 items)
- File pattern matching uses `glob::Pattern` for wildcard matching against file paths
- Migration script infers category/severity from tags and content keywords

### Skill Updates
- `claude-config/commands/learn.md` — Now calls `knowledge.capture()` + `knowledge.regenerate_rules()` instead of writing flat files
- `claude-config/commands/recall.md` — Now calls `knowledge.search()` with retrieval mode table instead of grep
- `claude-config/commands/start.md` — Now calls `knowledge.recent()` instead of listing learnings/ directory
- `claude-config/commands/wrap-up.md` — Now calls `knowledge.capture()` + `knowledge.regenerate_rules()` for session learnings

### Dependencies
- `rmcp 0.3.2` (same as other MCP servers)
- `rusqlite 0.32` with `bundled` feature (no system SQLite dependency)
- `serde_yaml 0.9` for YAML parsing
- `chrono 0.4` for date handling
- `glob 0.3` for file pattern matching
- `sha2 0.10` for content hashing

### Performance
- Index rebuild: ~20ms for 24 items (expect ~2-5s at 5000 items)
- Server startup: ~25ms total (load YAML + build index)
- FTS5 search: sub-millisecond for typical queries

## Verification
1. All 24 existing learnings migrated with correct scope + file_patterns
2. `search("nrf54l15 flashing")` returns relevant items
3. `for_context(["boards/nrf54l15dk_nrf54l15.overlay"])` returns nRF54L15 knowledge
4. `board_info("nrf54l15dk")` returns chip, flash method, memory map, errata
5. Auto-generated `rules/*.md` matches current manually-written content
6. `/learn` creates via MCP, not flat file
7. `/recall` searches via MCP, not grep

### Verified
- [x] 1. 24 items migrated (10 critical, 7 important, 7 informational)
- [x] 2. FTS5 search tested (test_db_index_and_search passes)
- [x] 3. File pattern matching tested (test_db_items_for_files passes)
- [x] 4. Board info tested (test_load_board_profiles passes)
- [x] 5. Live tested: search, for_context, board_info, for_chip, for_board, list_boards, list_tags, recent, regenerate_rules (6 files), regenerate_gotchas (10 items)
- [x] 6. /learn skill updated to use knowledge.capture() + knowledge.regenerate_rules()
- [x] 7. /recall skill updated to use knowledge.search() + other retrieval modes
