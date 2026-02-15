# Knowledge Server MCP

Status: Ideation
Created: 2026-02-15

## Problem

At thousands of learnings, grep-based search and rules files need supplementing with semantic search, cross-project knowledge sharing, and staleness analytics. The current three-tier system (CLAUDE.md Key Gotchas + `.claude/rules/` auto-injection + `/recall` grep search) works at small scale but won't scale to large teams or long timeframes.

## Approach

Build an MCP server that indexes the markdown learning files and provides tools for knowledge management:

- `search_learnings(query, tags?, date_range?)` — semantic search across learnings corpus
- `add_learning(title, body, tags)` — create a learning file atomically
- `list_tags(prefix?)` — discover tag vocabulary
- `stale_learnings(older_than_days?)` — find learnings that may be outdated

Fits the existing MCP server pattern (Rust, like zephyr-build/elf-analysis/embedded-probe). The architecture should index the same `learnings/YYYY/*.md` files used by the grep-based system, so both approaches work in parallel during transition.
