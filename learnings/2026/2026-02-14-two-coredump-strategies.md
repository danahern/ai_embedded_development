---
title: Two coredump strategies
date: 2026-02-14
author: danahern
tags: [coredump, architecture, rtt, dts]
---

- **RTT-only** (`debug_coredump.conf`): Simple, no flash partition needed. Data streams through RTT at crash time. Lost if no one is reading.
- **Flash-backed** (`debug_coredump_flash.conf`): Persists to flash, survives reboot. `crash_log` module re-emits on next boot. Needs a DTS overlay with `coredump_partition`.
