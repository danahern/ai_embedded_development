---
title: Log buffer drops during boot auto-report
date: 2026-02-14
author: danahern
tags: [coredump, logging, kconfig, zephyr]
---

When `crash_log` auto-emits a coredump at boot via `SYS_INIT`, the Zephyr deferred log buffer (not RTT buffer) overflows because boot messages from other subsystems compete. Symptom: "8 messages dropped" losing the `#CD:BEGIN#` and ZE header. Fix: increase `CONFIG_LOG_BUFFER_SIZE=4096` (default is 1024). Increasing `CONFIG_SEGGER_RTT_BUFFER_SIZE_UP` alone doesn't help — the bottleneck is the in-memory log message ring buffer.
