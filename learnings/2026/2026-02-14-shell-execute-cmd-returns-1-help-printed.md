---
title: shell_execute_cmd returns 1 when help is printed
date: 2026-02-14
author: danahern
tags: [testing, shell, zephyr]
---

When a shell command has a NULL handler (parent with subcommands only), the shell prints subcommand help and returns `SHELL_CMD_HELP_PRINTED` (1), not 0. Tests must call the full subcommand path (e.g., `"board info"` not `"board"`).
