---
title: size_report 'all' target produces one file, not two
date: 2026-02-15
author: danahern
tags: [elf-analysis, size-report, build-system]
---

Passing `all` as a positional arg to Zephyr's `size_report` script generates a single `all.json` combining ROM and RAM. To get separate `rom.json` and `ram.json`, pass `rom ram` as two separate positional args. The JSON output path uses `{target}` replacement — `all` replaces to `all`, not to separate files.
