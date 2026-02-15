# Learnings

Hard-won knowledge from building in this workspace, organized as a three-tier retrieval system.

## How It Works

| Tier | What | Where | When |
|------|------|-------|------|
| 1 | Critical gotchas | `CLAUDE.md` Key Gotchas section | Every session, always in context |
| 2 | Topic-focused rules | `.claude/rules/*.md` | Auto-injected when editing matching files |
| 3 | Full corpus | `learnings/YYYY/*.md` | On-demand via `/recall` skill |

## Adding Learnings

Use `/learn` during a session or `/wrap-up` at session end. Each learning is a single file:

```
learnings/YYYY/YYYY-MM-DD-kebab-slug.md
```

With YAML frontmatter: `title`, `date`, `author`, `tags`.

## Searching

- `/recall <topic>` — grep-based search by tag, title, or body
- `ls learnings/2026/` — browse by date
- `.claude/rules/` — curated summaries auto-injected by topic
