# CLAUDE.md Retrospective — 2026-02-28

**Scope:** Audit of all 32 CLAUDE.md files + 15 rules files for conflicts, gaps, staleness, and optimization.

## Files Audited

| Layer | Count | Notes |
|-------|-------|-------|
| Global | 1 | `~/.claude/CLAUDE.md` — behavioral guidelines |
| Workspace | 1 | Root `CLAUDE.md` — policy layer |
| MCP registry | 1 | `claude-mcps/CLAUDE.md` — server index |
| MCP servers | 11 | Individual server CLAUDE.md files |
| Firmware | 1 | `firmware/CLAUDE.md` — umbrella |
| Libraries | 12 | `firmware/lib/*/CLAUDE.md` |
| Other | 5 | config, test-tools, esp-idf apps, ospi-programmer |
| Rules | 15 | `.claude/rules/*.md` — auto-injected |

## Conflicts Found (6)

### 1. alif-flash description (FIXED)
- **Workspace CLAUDE.md**: "Alif E7 MRAM flash via SE-UART ISP protocol"
- **Reality**: E7/E8, J-Link primary, SE-UART for ATOC setup only
- **Fix**: Updated to "Alif E7/E8 flash via J-Link (primary) and SE-UART ISP (ATOC setup)"

### 2. linux-build default docker image (FIXED)
- **linux-build CLAUDE.md**: Documents `stm32mp1-sdk` as default
- **.mcp.json**: Overrides to `alif-e7-sdk:latest`
- **Fix**: Updated CLAUDE.md to show workspace-configured default

### 3. firmware/CLAUDE.md board config cross-reference (FIXED)
- **firmware/CLAUDE.md**: "See workspace CLAUDE.md for board mappings"
- **Reality**: Board table was removed from workspace CLAUDE.md
- **Fix**: Redirected to `knowledge.board_info()`

### 4. zephyr-build CLAUDE.md stale path (FIXED)
- **zephyr-build CLAUDE.md**: References `zephyr-apps/` submodule
- **Reality**: Apps are at `firmware/apps/`, configured via `--apps-dir`
- **Fix**: Updated to show actual workspace configuration

### 5. device_shell CLAUDE.md integration pattern
- Shows manual `ZEPHYR_EXTRA_MODULES` but `manifest.yml` auto-discovery exists
- **Status**: Deferred (low priority)

### 6. claude-mcps/CLAUDE.md missing servers (FIXED)
- Missing: `openocd-debug`, `knowledge-server` from table; `uart-mcp` from build section
- **Fix**: Added all missing entries

## Gaps Found (6)

1. **operational.md rules truncated** — cut off mid-sentence (FIXED via regenerate)
2. **firmware/CLAUDE.md over 8 KB** — at 10.2 KB, exceeds guideline (deferred)
3. **claude-config/CLAUDE.md too sparse** — 356 bytes, no agent/skill docs (deferred)
4. **ESP-IDF test projects lack CLAUDE.md** — covered by parent, low priority
5. **Typo "evalute"** in workspace CLAUDE.md (FIXED)
6. **Yocto example** in linux-build uses stale `build-stm32mp1` (FIXED)

## Staleness Summary

All high-priority stale items were fixed in this session. Remaining:
- `device_shell/CLAUDE.md` — could document manifest.yml auto-discovery
- `firmware/CLAUDE.md` — could be trimmed by ~2 KB (move C code to rules, trim test tables)
- `claude-config/CLAUDE.md` — needs expansion to document agents and skills

## Systemic Root Cause

**No automated consistency check between CLAUDE.md files and their ground-truth sources.** Cross-references break silently when content moves. MCP server additions don't propagate to all registry files.

**Prevention:** Add CLAUDE.md consistency check to `/wrap-up` skill — when `.mcp.json` or any CLAUDE.md changes, prompt review of affected cross-references.

## Agent & Context File Audit

Extended audit covering agents, skills, rules, hooks, and settings.

### Critical Fixes (Done)

1. **settings.local.json** — `alif-flash` and `uart` missing from `enabledMcpjsonServers` (FIXED)
2. **kernel-reviewer agent** — no `mcpServers` field, couldn't access any MCP tools (FIXED: added knowledge, linux-build)
3. **build-toolchain-expert agent** — missing `alif-flash`, `embedded-probe`, `elf-analysis` from mcpServers despite referencing them (FIXED)
4. **start.md & wrap-up.md** — referenced stale `zephyr-apps/` submodule instead of `firmware/`, `alif_arm-tf/`, `linux_alif/` (FIXED)
5. **bft.md** — Alif boards mapped to SSH/ADB deploy (not yet working) instead of `jlink_flash` (FIXED)
6. **embedded.md** — stale `zephyr-apps/` path in ELF example (FIXED)
7. **alif-e7-hardware.md rules** — stale MRAM-only layout, wrong DTB filename; updated to OSPI boot layout (FIXED)

### Systemic Patterns

- **Submodule/path drift**: When `firmware/` replaced `zephyr-apps/`, skills weren't updated
- **MCP enablement gap**: New servers registered but not added to `enabledMcpjsonServers`
- **Agent MCP access mismatch**: Agent body describes tools the frontmatter doesn't grant access to

## Actions Taken

- [x] Fixed workspace CLAUDE.md: alif-flash description, typo
- [x] Fixed firmware/CLAUDE.md: broken board config cross-reference
- [x] Fixed linux-build CLAUDE.md: default image, Yocto example, key details
- [x] Fixed claude-mcps/CLAUDE.md: added missing servers and build instructions
- [x] Fixed zephyr-build CLAUDE.md: stale zephyr-apps/ reference
- [x] Fixed operational.md rules truncation
- [x] Fixed settings.local.json: added alif-flash and uart to enabled servers
- [x] Fixed kernel-reviewer agent: added mcpServers
- [x] Fixed build-toolchain-expert agent: expanded mcpServers, noted Alif cross-compiler prefix
- [x] Fixed start.md and wrap-up.md: updated submodule lists
- [x] Fixed bft.md: Alif flash method → jlink_flash, added Alif section
- [x] Fixed embedded.md: stale zephyr-apps/ path
- [x] Fixed alif-e7-hardware.md: updated to OSPI boot layout

## Deferred Actions

- [ ] Trim firmware/CLAUDE.md from 10.2 KB to ~8 KB
- [ ] Expand claude-config/CLAUDE.md with agent/skill documentation
- [ ] Update device_shell CLAUDE.md with manifest.yml auto-discovery pattern
- [ ] Add CLAUDE.md consistency check to wrap-up skill
- [ ] Clean stale settings.local.json allow-rules (dead shell fragments, version-pinned JLink path)
- [ ] Fix hardware.md rules truncation (run regenerate_rules and verify)
- [ ] Narrow pattern.md rules file_patterns (too broad, injects into agent/CLAUDE.md edits)
