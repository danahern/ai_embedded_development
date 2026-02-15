---
title: OVERLAY_CONFIG vs DTC_OVERLAY_FILE
date: 2026-02-14
author: danahern
tags: [zephyr, build-system, kconfig, dts, overlay]
---

`OVERLAY_CONFIG` is for Kconfig fragments (`.conf` files). `DTC_OVERLAY_FILE` is for devicetree overlays (`.overlay` files). Zephyr auto-discovers DTS overlays from `boards/` but you must explicitly list Kconfig overlays via `OVERLAY_CONFIG`.
