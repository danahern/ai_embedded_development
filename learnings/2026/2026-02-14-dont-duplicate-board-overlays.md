---
title: Don't duplicate board overlays — use library's boards/ directory
date: 2026-02-14
author: danahern
tags: [zephyr, build-system, dts, overlay]
---

When a library (e.g. crash_log) provides board-specific DTS overlays in its `boards/` directory, apps should NOT copy those overlays into their own `boards/` directory. Zephyr auto-discovers overlays from the app's `boards/` dir, but the library's overlays are included via `DTC_OVERLAY_FILE` in CMakeLists.txt. Duplicating them causes maintenance drift and confusion about which is authoritative.
