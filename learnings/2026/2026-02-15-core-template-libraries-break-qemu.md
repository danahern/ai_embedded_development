---
title: Core template libraries break QEMU builds
date: 2026-02-15
author: danahern
tags: [build-system, qemu, testing, kconfig]
---

The `create_app` core template includes crash_log and device_shell library overlays which enable RTT and flash — both unavailable on `qemu_cortex_m3`. For QEMU-only apps, remove the `OVERLAY_CONFIG` lines from CMakeLists.txt.
