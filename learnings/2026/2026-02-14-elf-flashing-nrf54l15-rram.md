---
title: ELF flashing can fail on nRF54L15 RRAM
date: 2026-02-14
author: danahern
tags: [nrf54l15, rram, flashing, probe-rs]
---

probe-rs sometimes fails to flash ELF files on nRF54L15 (RRAM-based flash). Fall back to `.hex` files: `flash_program(session_id, file_path="build/zephyr/zephyr.hex")`.
