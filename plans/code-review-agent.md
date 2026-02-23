# Code Review Agent

**Status**: Complete

## Problem

Knowledge items capture hard-won lessons (BLE callbacks must not block, UTF-8 string slicing panics, DTB round-trip corruption, etc.) but they're passive — they only help if they happen to be in context when code is written. Tier 2 rules auto-inject when editing matching files, but Claude may not check them before committing a pattern violation.

A code review agent actively checks diffs against the knowledge store, catching known anti-patterns before they ship.

## Approach

Knowledge-powered reviewer that connects changed files to relevant knowledge items and checks for violations.

### Flow

1. **Trigger**: After code changes are written (pre-commit or on-demand via `/review`)
2. **Gather context**: `git diff --staged` or unstaged diff to identify changed files and hunks
3. **Query knowledge**: Call `knowledge.for_context(files=changed_files)` to get relevant knowledge items
4. **Pattern match**: For each relevant knowledge item, check if the diff introduces a known anti-pattern:
   - Item says "BLE GATT callbacks must not block" → scan GATT callback functions for blocking calls (WiFi connect, NVS write, semaphore take)
   - Item says "never round-trip DTB through dtc" → check for `dtc -I dtb -O dts` in scripts
   - Item says "MCP servers must have unit tests" → check if new MCP tool handlers have corresponding tests
5. **Report**: Surface violations with the knowledge item title, severity, and a one-line explanation

### What it is NOT

- Not a general linter (clippy, pylint already exist)
- Not a style checker
- Focused specifically on **domain knowledge violations** — the things that only bite you if you've been through it before

### Implementation Options

**Option A: Claude Code skill (`/review`)**
- Skill that spawns an Explore agent with the diff + knowledge context
- Agent reads the diff, queries knowledge, reasons about violations
- Returns a report
- Pros: Simple, no new infrastructure. Uses Claude's reasoning for fuzzy matching.
- Cons: Costs tokens on every review. May be slow for large diffs.

**Option B: PreToolUse hook**
- Hook that fires before `git commit`, queries knowledge for changed files
- Lightweight check — pattern-match file paths against knowledge items, inject warnings
- Pros: Automatic, zero friction
- Cons: Hooks can't do complex reasoning. Limited to file-pattern matching.

**Option C: Hybrid**
- Hook does fast file-pattern check (are there relevant knowledge items for these files?)
- If yes, spawns the review agent for deeper analysis before commit
- Best of both: automatic trigger, intelligent review

### Recommended: Option A first, evolve to C

Start with a `/review` skill that's explicitly invoked. Learn what kinds of violations it catches well. Then add the hook trigger once the review logic is proven.

## Solution

Option A — a `/review` skill prompt in `claude-config/commands/review.md`. The skill:

1. Gets staged diff (falls back to unstaged if nothing staged)
2. Extracts changed file paths from the diff
3. Calls `knowledge.for_context(files=...)` to load relevant knowledge items
4. Reviews added/modified lines against each knowledge item for anti-pattern violations
5. Reports findings with severity, knowledge item title, file location, and fix suggestion

## Open Questions (Resolved)

- **Full body or just title?** → Full body — Claude needs the anti-pattern description to reason about violations
- **New lines only or context too?** → Only flag new/modified lines, but may read surrounding context to determine if a pattern is actually violated
- **False positive handling** → Skill uses high-confidence threshold; uncertain matches reported as suggestions, not findings
- **Wrap-up integration** → Deferred — let the skill prove useful standalone first

## Tasks

- [x] Design the `/review` skill prompt
- [x] Test with known violations (BLE callback blocking — both knowledge items fired correctly)
- [x] Evaluate signal-to-noise ratio (2 findings, both true positives, zero false positives)
- [ ] If useful, add hook trigger (Option C)
