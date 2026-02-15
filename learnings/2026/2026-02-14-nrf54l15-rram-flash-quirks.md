---
title: nRF54L15 RRAM flash quirks
date: 2026-02-14
author: danahern
tags: [nrf54l15, rram, flashing, probe-rs, dts]
---

- `flash_program` with `.hex` works directly without prior erase
- `run_firmware` (erase+program) fails on nRF54L15 RRAM
- `flash_erase` followed by `flash_program` also fails
- `connect_under_reset=true` helps recover from stuck states
- nRF54L15 RRAM is exactly 1524KB (0x17D000). Default storage fills to the end — must shrink storage to fit a coredump partition
