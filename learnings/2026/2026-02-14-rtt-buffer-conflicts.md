---
title: RTT buffer conflicts between log and shell backends
date: 2026-02-14
author: danahern
tags: [rtt, kconfig, shell, logging]
---

`CONFIG_LOG_BACKEND_RTT` and `CONFIG_SHELL_BACKEND_RTT` both default to buffer 0. When using both, set `CONFIG_SHELL_BACKEND_RTT_BUFFER=1` or the build fails with "Conflicting log RTT backend enabled on the same channel."
