# Structured Learnings System

Status: Complete
Created: 2026-02-15

## Problem

The learnings system (`learnings/*.md`) is a manual, load-everything-at-startup approach that breaks at scale. The real problem isn't storage format — it's **retrieval**: how does the right learning reach Claude at the right time without bloating context?

At hundreds of engineers over years, "read all learnings at session start" is impossible. We need a system where:
- Claude never relearns the same thing twice
- Context isn't bloated with thousands of irrelevant learnings
- Critical knowledge surfaces automatically when relevant
- New learnings are captured atomically with metadata
- Temporal learnings (board-specific, project-specific) fade naturally while evergreen knowledge persists

## Approach

Three-tier retrieval architecture:

1. **Tier 1: Always loaded** (CLAUDE.md Key Gotchas) — 10-15 most critical learnings, always in context
2. **Tier 2: Auto-injected** (`.claude/rules/`) — Topic-focused rule files with path globs, auto-injected when working on matching files
3. **Tier 3: On-demand** (`/recall` skill) — Grep-based search across the full learnings corpus

Storage: one learning per file in `learnings/YYYY/`, YAML frontmatter with tags, date-prefixed filenames.

## Solution

### Deliverables
- `.claude/rules/` with 5 topic files (nrf54l15, coredump, testing, build-system, rtt)
- `/learn` skill — capture learnings with metadata, auto-update rules files
- `/recall` skill — grep-based search across learnings corpus
- 23 individual learning files migrated from 5 topic files
- Updated `/start` and `/wrap-up` skills for tiered approach
- Updated `LEARNINGS.md` and `CLAUDE.md` documentation
- 3 ideation plans migrated from LEARNINGS.md Ideas section

### File format
```markdown
---
title: Short descriptive title
date: YYYY-MM-DD
author: name
tags: [tag1, tag2, tag3]
---

Body text explaining the learning.
```

### Tag conventions
| Category | Examples |
|----------|----------|
| Chips | `nrf52840`, `nrf54l15`, `esp32`, `esp32s3` |
| Subsystems | `zephyr`, `bluetooth`, `coredump`, `shell`, `dts`, `kconfig` |
| Tools | `probe-rs`, `twister`, `west`, `size-report`, `rtt` |
| Concepts | `flashing`, `testing`, `build-system`, `memory`, `overlay` |
| Platforms | `macos`, `linux`, `qemu` |

## Verification

1. `.claude/rules/` directory exists with 5 topic files, each with valid `paths:` frontmatter
2. `ls learnings/2026/*.md | wc -l` returns 23
3. Old topic files (hardware.md, etc.) are deleted
4. Grep `tags:.*nrf54l15` in `learnings/2026/` finds the RRAM-related files
5. `/learn` skill exists and includes the step to update `.claude/rules/` topic files
6. `/recall` skill exists and demonstrates grep-based search
7. `/start` references the new tiered approach (not "read all learnings")
8. CLAUDE.md documents the three-tier system and tag conventions
9. Manual test: invoke `/recall nrf54l15` and confirm it finds relevant learnings
10. Ideas & Future Work section removed from `LEARNINGS.md`
11. `plans/esp-idf-crash-analysis.md` and `plans/shared-library-candidates.md` exist with Ideation status
12. `plans/knowledge-server-mcp.md` exists with Ideation status

## Implementation Notes

Files created/modified:
- `.claude/rules/` — 5 new topic files (nrf54l15, coredump, testing, build-system, rtt)
- `claude-config/commands/learn.md` — new `/learn` skill
- `claude-config/commands/recall.md` — new `/recall` skill
- `claude-config/commands/start.md` — updated step 1 for tiered approach
- `claude-config/commands/wrap-up.md` — updated steps 2 and 4
- `learnings/2026/` — 23 individual learning files migrated from 5 topic files
- `learnings/*.md` — 5 old topic files deleted
- `LEARNINGS.md` — replaced with three-tier system description
- `CLAUDE.md` — updated Learnings section with three-tier docs, tag conventions, added /learn and /recall to Key Commands
- `plans/esp-idf-crash-analysis.md` — new Ideation plan
- `plans/shared-library-candidates.md` — new Ideation plan
- `plans/knowledge-server-mcp.md` — new Ideation plan

All 12 verification checks pass.

## Modifications

None — implemented as planned.
