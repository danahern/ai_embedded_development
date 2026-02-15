---
title: In-memory coredump backend for testing
date: 2026-02-14
author: danahern
tags: [coredump, testing, qemu, kconfig]
---

`CONFIG_DEBUG_COREDUMP_BACKEND_IN_MEMORY` provides the same query/copy API as the flash backend. Works on QEMU for unit testing crash_log without real flash hardware.
