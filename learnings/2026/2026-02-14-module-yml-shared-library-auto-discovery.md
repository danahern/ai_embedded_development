---
title: Use zephyr/module.yml for shared library auto-discovery
date: 2026-02-14
author: danahern
tags: [zephyr, build-system, kconfig]
---

Instead of setting `ZEPHYR_EXTRA_MODULES` in every app's CMakeLists.txt, place a `zephyr/module.yml` at the repo root pointing to a top-level `lib/CMakeLists.txt` and `lib/Kconfig`. Apps just enable `CONFIG_<LIB>=y` in prj.conf. This eliminates boilerplate and ensures new apps get all libraries automatically.
