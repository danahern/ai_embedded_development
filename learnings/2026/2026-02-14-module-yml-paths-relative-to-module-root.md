---
title: module.yml paths are relative to module root, not the yml file
date: 2026-02-14
author: danahern
tags: [zephyr, build-system, kconfig]
---

`zephyr/module.yml` paths (`cmake:`, `kconfig:`) resolve relative to the module root (the parent of `zephyr/`), not relative to `module.yml` itself. Use `cmake: .` and `kconfig: Kconfig`, not `cmake: ..` / `kconfig: ../Kconfig`.
