---
title: Shell command name conflicts with Zephyr builtins
date: 2026-02-14
author: danahern
tags: [zephyr, shell]
---

Zephyr has a built-in `device` shell command (`subsys/shell/modules/device_service.c` with subcommands `list` and `init`). Custom shell commands must pick unique names. We renamed ours to `board` after debugging why `shell_execute_cmd(sh, "device info")` returned 1 instead of 0 — it was dispatching to Zephyr's built-in, not ours.
