---
title: Flash-dependent code can't run on QEMU
date: 2026-02-14
author: danahern
tags: [testing, qemu, coredump, kconfig]
---

`CONFIG_DEBUG_COREDUMP_BACKEND_FLASH_PARTITION` requires `FLASH_HAS_DRIVER_ENABLED` which QEMU doesn't provide. For tests that need flash, use `build_only: true` with `platform_allow` for real boards, or find an alternative test strategy.
