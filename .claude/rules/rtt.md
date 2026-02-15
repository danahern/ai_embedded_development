---
paths: ["**/*.conf", "**/*.dts", "**/*.dtsi", "**/*.overlay", "**/*RTT*", "**/*coredump*", "**/*crash*", "**/*dump*", "**/*rtt*", "**/*shell*", "**/Kconfig*"]
---
# Rtt Learnings

- **RTT buffer conflicts between log and shell backends** — `CONFIG_LOG_BACKEND_RTT` and `CONFIG_SHELL_BACKEND_RTT` both default to buffer 0. When using both, set `CONFIG_SHELL_BACKEND_RTT_BUFFER=1` or the build fails with "Conflicting log RTT backend enabled on the same channel."
- **Two coredump strategies** — - **RTT-only** (`debug_coredump.conf`): Simple, no flash partition needed. Data streams through RTT at crash time. Lost if no one is reading.
- **RTT output arrives in chunks** — When capturing coredump data via `rtt_read`, output arrives in ~1KB chunks. Concatenate all reads until `#CD:END#` appears before passing to `analyze_coredump`. Lines can split across chunk boundaries.
- **Coredump size and RTT buffer** — `CONFIG_DEBUG_COREDUMP_MEMORY_DUMP_MIN=y` captures only the faulting thread's stack, which fits in the default 4KB RTT buffer. `MEMORY_DUMP_LINKER_RAM` captures all RAM and will overflow RTT — only use with flash backend.
