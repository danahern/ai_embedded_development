# Workspace Cleanup

Status: Complete
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

## Solution

Most items were resolved organically during other work:

- **`crash_debug/boards/` duplication** — Resolved. Directory no longer exists; overlays live only in `lib/crash_log/boards/`.
- **`debug_config/` directory** — Resolved. Consolidated into `lib/crash_log/conf/` during earlier cleanup.
- **`apps_dir` hardcoded** — Resolved. `zephyr-build` config.rs already accepts `--apps-dir` CLI arg with `"zephyr-apps/apps"` default.
- **WiFi SSID/PSK in prj.conf** — Not a real issue. Values are `"your_ssid"` placeholders, and `local.conf.example` pattern is already in place for real credentials.
- **Debug coredump conf duplication** — Not worth extracting. The two files share only 1 line (RTT buffer size) and serve different use cases (RTT-only vs flash-backed). Extracting a common fragment adds complexity for no benefit.
