# ELF / Size Analysis Learnings

**size_report `all` target produces one file, not two.** Passing `all` as a positional arg to Zephyr's `size_report` script generates a single `all.json` combining ROM and RAM. To get separate `rom.json` and `ram.json`, pass `rom ram` as two separate positional args. The JSON output path uses `{target}` replacement — `all` replaces to `all`, not to separate files.

**Core template libraries break QEMU builds.** The `create_app` core template includes crash_log and device_shell library overlays which enable RTT and flash — both unavailable on `qemu_cortex_m3`. For QEMU-only apps, remove the `OVERLAY_CONFIG` lines from CMakeLists.txt.
