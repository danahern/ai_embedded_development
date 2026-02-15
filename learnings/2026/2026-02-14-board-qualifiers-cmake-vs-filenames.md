---
title: Board qualifiers use / in CMake, _ in filenames
date: 2026-02-14
author: danahern
tags: [zephyr, build-system, dts, overlay]
---

`${BOARD}` expands to `nrf52840dk/nrf52840` (with `/`) but DTS overlay files use `_` separator: `nrf52840dk_nrf52840.overlay`. Don't set `DTC_OVERLAY_FILE` manually — put overlays in the app's `boards/` directory and let Zephyr auto-discover them.
