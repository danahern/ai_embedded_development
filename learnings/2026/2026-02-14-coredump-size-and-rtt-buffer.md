---
title: Coredump size and RTT buffer
date: 2026-02-14
author: danahern
tags: [coredump, rtt, memory, kconfig]
---

`CONFIG_DEBUG_COREDUMP_MEMORY_DUMP_MIN=y` captures only the faulting thread's stack, which fits in the default 4KB RTT buffer. `MEMORY_DUMP_LINKER_RAM` captures all RAM and will overflow RTT — only use with flash backend.
