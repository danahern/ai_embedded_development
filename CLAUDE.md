# Embedded Development Workspace

## Collaboration Style
- Act like a senior engineer, evalute requests, if there is a better way propose it.  This is a collaborative project.

**Ask questions and propose approaches before diving into implementation.**

- Propose an approach first when multiple paths exist. Surface tradeoffs.
- If you hit something unexpected, explain what you found and ask which direction to go.
- When a task touches multiple subsystems, outline the pieces and confirm scope before starting.

## Key Gotchas

Cross-cutting lessons (Tier 1 — always loaded). Board/platform-specific gotchas auto-inject via `.claude/rules/` (Tier 2). Full corpus via `/recall` or `knowledge.search()` (Tier 3).

- **MCP server testing**: MCP servers MUST have unit tests for core logic (ID generation, parsing, encoding). Silent bugs are destructive.

## CRITICAL: MCP-First Policy

**ALWAYS use MCP tools. NEVER shell out to CLI equivalents.** Hooks enforce this — blocked commands will tell you which MCP tool to use instead. If an MCP tool fails, STOP and tell the user — fix the MCP server, don't work around it.

## CRITICAL: Learn and Retain

**When you discover the right approach to something, verify it works first, then capture it so it loads automatically next session.**

1. **Verify before capturing** — Don't capture knowledge on first discovery. Confirm the approach actually works end-to-end. Wrong knowledge is worse than no knowledge.
2. **Capture after confirmation** — Once verified working, use `knowledge.capture()` or `/learn` for hardware discoveries, protocol quirks, tooling constraints.
3. **Update rules** — If the learning affects how you interact with specific files or hardware, add or update a `.claude/rules/*.md` file so it auto-injects when relevant files are edited.
4. **Update gotchas** — If it's critical enough to affect every session, add it to the Key Gotchas section above and run `knowledge.regenerate_gotchas()`.
5. **Never repeat the same mistake** — If you find yourself doing the same wrong thing twice, that's a signal the knowledge wasn't captured correctly. Stop and fix the knowledge gap before continuing.

## MCP Servers

Tool signatures are in each server's own CLAUDE.md (`claude-mcps/<server>/CLAUDE.md`). Available servers:

- **zephyr-build** — Build, test, scaffold Zephyr apps (west wrapper)
- **elf-analysis** — ROM/RAM size analysis, diffing, top consumers
- **esp-idf-build** — ESP-IDF build, flash, monitor
- **linux-build** — Docker cross-compilation, SSH/ADB deployment, Yocto builds
- **embedded-probe** — Debug probes, flash programming, RTT, coredump analysis, nrfutil
- **knowledge** — Knowledge capture, search, board profiles, rule/gotcha regeneration
- **saleae-logic** — Logic analyzer capture and protocol decoding
- **hw-test-runner** — BLE GATT, WiFi provisioning, TCP throughput testing
- **alif-flash** — Alif E7 MRAM flash via SE-UART ISP protocol

Board details available via `knowledge.board_info("board_name")` or `knowledge.list_boards()`.

## Workflows

Use `/bft <app> <board>` (build-flash-test), `/hw-verify <app> <board>` (hardware verification), or `/embedded` (full guidelines including crash debug).

## Plans

Plans in `plans/` track significant work (new MCPs, skills, agents, apps, libs, or changes touching 5+ files). Status lifecycle: `Ideation` → `Planned` → `In-Progress` → `Complete`. Descriptive kebab-case names, git-tracked.

**Rules:** Create plan file BEFORE starting implementation. Update incrementally during work. Never mark Complete until all verification passes. The `plans/` file is the single source of truth — not session drafts.

## Project Documentation

- **Significant components** (MCPs, skills, agents, apps, libs) — `README.md` + `PRD.md` + `CLAUDE.md` + plan
- **Small components** — `CLAUDE.md` only is sufficient

## Testing

**All code must be unit tested — apps, libraries, AND MCP servers.** Test failure cases, not just happy path. Cover edge cases: invalid input, missing files, empty data, error conditions. MCP servers: test core logic (ID generation, parsing, encoding) — these bugs are silent and destructive.

## Knowledge

Three-tier retrieval delivers the right knowledge at the right time:

| Tier | What | Where | When |
|------|------|-------|------|
| 1 | Critical gotchas | `CLAUDE.md` Key Gotchas section | Every session, always in context |
| 2 | Topic rules | `.claude/rules/*.md` (auto-generated) | Auto-injected when editing matching files |
| 3 | Full corpus | `knowledge/items/*.yml` | On-demand via `/recall` or `knowledge.search()` |

Capture with `/learn` or `/wrap-up`. Regenerate derived files with `knowledge.regenerate_gotchas()` (Tier 1) and `knowledge.regenerate_rules()` (Tier 2).

## Workspace Structure

`firmware/` (Zephyr/ESP-IDF apps + shared libs), `claude-mcps/` (MCP servers, submodule), `claude-config/` (skills/agents, submodule), `knowledge/` (items + board profiles), `test-tools/` (Python BLE/power utils), `plans/` + `retrospective/`. West-managed deps: `zephyr/`, `bootloader/`, `modules/`, `tools/` (gitignored).

## Key Commands

- `/start` — Bootstrap session (recent knowledge, hardware check, git status)
- `/wrap-up` — End session (capture knowledge, commit work)
- `/learn` — Capture a knowledge item with metadata and tags
- `/recall` — Search knowledge by topic, tag, or keyword
- `/embedded` — Full embedded development guidelines (memory, style, Zephyr patterns)
- `/bft <app> <board>` — Build, flash, validate boot, read output — single command inner loop
- `/hw-verify <app> <board>` — Guided hardware verification checklist
