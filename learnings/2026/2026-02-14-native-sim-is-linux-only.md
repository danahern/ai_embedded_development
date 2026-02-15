---
title: native_sim is Linux-only
date: 2026-02-14
author: danahern
tags: [testing, macos, qemu, zephyr]
---

The POSIX architecture (`native_sim`, `native_posix`) doesn't work on macOS. Use `qemu_cortex_m3` for unit tests that need an ARM target.
