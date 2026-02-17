# Knowledge Item UUID IDs

Status: Complete
Created: 2026-02-17

## Problem

Knowledge item IDs use a date-based sequential format (`k-2026-0217-001`). The sequence number is calculated by scanning in-memory items for the max sequence on that date and incrementing. This causes **ID collisions when multiple sessions create items on the same day** — the second session doesn't see items created by the first (they're only on disk, not in its in-memory map), so it reuses sequence numbers and overwrites existing YAML files.

We hit this in practice: session A created `k-2026-0217-001` through `003`, then session B's `capture()` generated the same IDs and overwrote the files.

## Approach

Replace date-sequential IDs with UUIDs. The system already treats IDs as opaque `String`/`TEXT` values throughout — database, HashMap, YAML, file paths, cross-references. Only two functions assume the format: `generate_id()` and `next_sequence()`.

**Format**: `k-<uuid-v4>` (e.g., `k-a1b2c3d4-e5f6-7890-abcd-ef1234567890`). Keep the `k-` prefix for greppability and to distinguish knowledge IDs from other UUIDs in the codebase.

**Backward compatible**: Existing `k-YYYY-MMDD-NNN` items continue to work unchanged. No migration needed — old and new IDs coexist as opaque strings.

## Solution

### Changes

**`knowledge.rs`** (2 lines):
- Replace `generate_id(date, sequence)` with `generate_id()` that returns `format!("k-{}", Uuid::new_v4())`
- Add `uuid` crate dependency

**`tools/handler.rs`** (3 lines):
- Remove `next_sequence()` method entirely (~20 lines deleted)
- Change capture handler to call `KnowledgeItem::generate_id()` with no args
- Remove `today` date variable from ID generation (still needed for `created` field)

**`Cargo.toml`** (1 line):
- Add `uuid = { version = "1", features = ["v4"] }`

**Tests** (~10 lines):
- Update `generate_id` unit tests to verify `k-` prefix and UUID format
- Remove `next_sequence` prefix-matching tests (function deleted)
- Integration tests: verify capture returns a valid `k-<uuid>` ID

### Files changed

| File | Change |
|------|--------|
| `claude-mcps/knowledge-server/Cargo.toml` | Add uuid dependency |
| `claude-mcps/knowledge-server/src/knowledge.rs` | Simplify `generate_id()` |
| `claude-mcps/knowledge-server/src/tools/handler.rs` | Remove `next_sequence()`, simplify capture |
| `claude-mcps/knowledge-server/tests/integration_tests.rs` | Update ID format assertions |

### Not changed

- Database schema (id is already `TEXT PRIMARY KEY`)
- YAML file format (id field stays a string)
- File naming (`{id}.yml` — UUIDs are valid filenames)
- All queries, lookups, FTS5 index (all use string comparison)
- Existing knowledge items (old IDs remain valid)
- `superseded_by` references (string-to-string)
- `deprecate`, `validate`, `search`, `for_context` tools (all ID-agnostic)

## Implementation Notes

- Total diff: ~20 lines deleted (next_sequence + old tests), ~15 lines added (uuid logic + new tests)
- `uuid` crate v1 with `v4` feature adds ~20KB to release binary
- Old `k-YYYY-MMDD-NNN` items coexist with new `k-<uuid>` items — no migration needed
- `load_all_items` sorts by ID; UUIDs sort lexicographically which is fine (no ordering guarantee needed)

## Verification

- [x] `cargo test` passes — 14 passed, 3 ignored (workspace-dependent)
- [x] `cargo build --release` succeeds
- [x] `generate_id()` returns `k-<uuid>` format
- [x] Two generated IDs are never equal (unit test)
- [x] UUID portion parses as valid UUID v4 (unit test)
- [x] `capture()` live test — returns `k-<uuid>` format ID (verified: `k-0195b093-811e-4a2a-bfd5-b479a593eba0`)
- [x] Existing `k-2026-*` items still load and search correctly (verified: search, recent both return old IDs)
