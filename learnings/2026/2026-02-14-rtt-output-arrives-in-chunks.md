---
title: RTT output arrives in chunks
date: 2026-02-14
author: danahern
tags: [rtt, coredump, probe-rs]
---

When capturing coredump data via `rtt_read`, output arrives in ~1KB chunks. Concatenate all reads until `#CD:END#` appears before passing to `analyze_coredump`. Lines can split across chunk boundaries.
