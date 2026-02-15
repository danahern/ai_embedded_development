# Workspace Cleanup

Status: Ideation
Created: 2026-02-15

## Problem

Several small cleanup tasks accumulated during initial development. None are blockers, but they create confusion or minor tech debt:

- `apps/crash_debug/boards/` duplicates `lib/crash_log/boards/` overlays — maintenance drift risk
- `ble_wifi_bridge/prj.conf` has hardcoded WiFi SSID/PSK that should be gitignored
- `debug_coredump.conf` and `debug_coredump_flash.conf` share ~15 lines of common config that could be extracted
- `debug_config/` directory only holds two .conf files used exclusively with crash_log — should be folded into `crash_log/conf/`
- `apps_dir` is hardcoded in zephyr-build MCP's config.rs — should accept CLI arg or config file override

## Approach

Batch these as a single cleanup pass. Each is independent and low-risk.
