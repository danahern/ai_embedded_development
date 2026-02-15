---
title: Gitignore negation requires wildcard, not directory slash
date: 2026-02-15
author: danahern
tags: [git, build-system]
---

Git's `.gitignore` negation (`!path`) doesn't work when the parent is ignored with a trailing slash (e.g., `.claude/`). The slash makes git skip the entire directory without checking children. Use a wildcard instead: `.claude/*` with `!.claude/rules/` to ignore everything in `.claude/` except `rules/`.
