---
title: coredump_cmd return values
date: 2026-02-14
author: danahern
tags: [coredump, zephyr, api]
---

`coredump_cmd(COREDUMP_CMD_COPY_STORED_DUMP)` returns positive byte count on success, not 0. Check `if (ret <= 0)` for errors, and use `ret` as the actual bytes copied for iteration.
