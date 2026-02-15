# Shared Library Candidates

Status: Ideation
Created: 2026-02-15

## Problem

Several patterns keep repeating across apps that could be extracted into shared libraries in `zephyr-apps/lib/`:

- **BLE NUS abstraction** — Already exists in `ble_wifi_bridge`, could extract to a shared library
- **Logging configuration helper** — Standardize RTT vs UART vs both
- **OTA DFU shell commands** — MCUboot-based firmware update management via shell

## Approach

Extract common patterns into shared libraries following the same structure as `crash_log` and `device_shell`. Each library would have its own Kconfig, CMakeLists.txt, board overlays, and tests. Auto-discovered via the workspace `zephyr/module.yml`.
