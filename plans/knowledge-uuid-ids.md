# Knowledge Item UUID IDs

Status: Planned
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

## Verification

- [ ] `cargo test` passes in knowledge-server
- [ ] `capture()` returns `k-<uuid>` format ID
- [ ] New YAML file created with UUID filename
- [ ] Existing `k-2026-*` items still load and search correctly
- [ ] `deprecate(id, superseded_by)` works with mixed old/new IDs
- [ ] Two concurrent captures never collide
