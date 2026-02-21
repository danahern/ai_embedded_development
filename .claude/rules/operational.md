---
paths: ["**/knowledge-server/src/tools/handler.rs", ".claude/commands/**", ".mcp.json"]
---
# Operational Learnings

- **regenerate_gotchas() now requires validated status** — The regenerate_gotchas() function in knowledge-server now filters by `status == "validated"` in addition to `severity == "critical"` and `!deprecated`. Only validated critical items reach Tier 1 (CLAUDE.md Key Gotchas). The output JSON includes `unvalidated_critical_count` and `unvalidated_critical` array showing items excluded due to unvalidated status. This prevents unvetted advice from being promoted to always-in-context gotchas.
- **MCP setup on new machine: build servers, symlink skills, restart** — When setting up the workspace on a new machine:
