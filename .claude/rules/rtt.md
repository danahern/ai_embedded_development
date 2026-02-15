---
paths: ["**/*rtt*", "**/prj.conf", "**/*.conf"]
---
# RTT Learnings

- **Output arrives in ~1KB chunks** — concatenate all reads until `#CD:END#` before passing to `analyze_coredump`. Lines can split across boundaries.
- **LOG_BACKEND_RTT and SHELL_BACKEND_RTT conflict on buffer 0** — set `CONFIG_SHELL_BACKEND_RTT_BUFFER=1` when using both.
- **Shell naming conflicts** — Zephyr has built-in `device` shell command. Pick unique names for custom commands.
