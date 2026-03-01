# Workspace Retrospective — 2026-02-28

**Scope:** Full workspace health review — project structure, MCP servers, knowledge system, plans, code quality, process
**Prior retrospective:** `analysis.md` (2026-02-17, ~14 days ago)

## Overall Assessment

The workspace is in good health for a ~2-week-old project in active hardware bring-up. The foundational architecture (knowledge tiers, MCP-first, plan lifecycle, agent specialization) is sound and working. The previous retrospective's Tier 1 actions were executed well.

## Metrics Snapshot

| Metric | Value | vs. 2026-02-17 | Assessment |
|--------|-------|----------------|------------|
| MCP servers | 11 registered | +2 (uart, openocd-debug) | Growing well |
| Knowledge items | 218 | +113 | Strong velocity |
| Validated items | 66 (30%) | Unknown baseline | Gap widening |
| Unvalidated items | 152 (70%) | Growing faster than validation | Risk |
| Plans total | 49 | +~15 | Good |
| Plans complete | 30 (61%) | Maintained | Stable |
| Agents | 8 | +2 (kernel-reviewer, build-toolchain-expert) | Growing |

## Keep Doing

- **Three-tier knowledge system** — YAML → SQLite FTS5 → auto-rules → gotchas is the standout engineering achievement
- **Plan-driven development** — 61% completion rate with well-maintained status tracking
- **Session lifecycle discipline** — `/start` and `/wrap-up` create clean session boundaries
- **MCP-first with hook enforcement** — eliminates tool-use anti-patterns
- **Heavy testing on alif-flash** — 115 tests on the most hardware-critical server
- **`/bft` skill** — addressed the previous retro's biggest efficiency gap

## Start / Change

1. **Filter `regenerate_rules()` by validation status** — Tier 2 rules still inject unvalidated advice
2. **Create a `/validate` skill** — systematic way to work through 152 unvalidated knowledge items
3. **Update CLAUDE.md server list** when adding servers — `uart` and `openocd-debug` missing
4. **Add esp-idf-build tests** — only 6 tests, thinnest coverage of any server
5. **Fix `linux-build` default** — hardcoded to `stm32mp1-sdk`, should be `alif-e7-sdk`
6. **Update `alif-e7-adb-gadget.md` plan** — CDC-ECM working but plan still In-Progress

## Stop Doing

- **Capturing knowledge faster than validating it** — 70% unvalidated, ratio worsening
- **Adding MCP servers without updating workspace CLAUDE.md** — happened twice
- **Letting `settings.local.json` grow unchecked** — 134 allow-rules, some conflict with hooks
- **Leaving Ideation plans indefinitely** — 7 plans from mid-Feb with no activity

## Risks

| Risk | Severity | Description |
|------|----------|-------------|
| Knowledge validation debt | **High** | 152 unvalidated items. Tier 2 rules don't filter by status |
| OSPI flash speed | Medium | JLink at ~7 KB/s = 8.5 min for kernel. RTT blocked, UART todo |
| E8 hardware dependency | Medium | Onboarding plan can't advance without board |
| settings.local.json vs hook conflict | Low | Allow-rules may bypass MCP-first hook |

## Test Coverage

```
alif-flash:      115 tests  Excellent
embedded-probe:   55 tests  Good
zephyr-build:     45 tests  Good
uart-mcp:         35 tests  Good
saleae-logic:     33 tests  Good
hw-test-runner:   29 tests  Good
linux-build:      19 tests  Adequate
knowledge-server: 19 tests  Adequate
elf-analysis:     16 tests  Adequate
openocd-debug:    16 tests  Adequate
esp-idf-build:     6 tests  Thin — needs attention
```

## Action Plan

### Do Now
1. Update workspace CLAUDE.md with `uart` and `openocd-debug` servers
2. Update `alif-e7-adb-gadget.md` plan status
3. Fix `linux-build` default docker image in `.mcp.json`

### Do Soon
4. Add validation filter to `regenerate_rules()` in knowledge-server
5. Create `/validate` skill for systematic knowledge review
6. Add test coverage to `esp-idf-build` (target 15+ tests)
7. Add "update CLAUDE.md server list" to wrap-up checklist

### Do Later
8. Audit `settings.local.json` allow-rules vs enforcement hook
9. Define Ideation plan SLA (30-day archive policy)
10. Advance `uart-ospi-flash.md` from Todo to active planning
