---
title: Zephyr coredump captures exception frame registers
date: 2026-02-14
author: danahern
tags: [coredump, zephyr, debugging]
---

The coredump subsystem captures PC/LR/SP from the ARM exception frame — the actual crash site. This is better than halting after a fault and reading registers, which only shows the fault handler context.
