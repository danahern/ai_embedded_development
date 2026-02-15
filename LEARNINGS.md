# Learnings

Hard-won knowledge from building in this workspace. Split by topic:

- [Zephyr Build System](learnings/zephyr-build.md)
- [Testing on macOS](learnings/testing.md)
- [MCP / Hardware Workflow](learnings/hardware.md)
- [Architecture Decisions](learnings/architecture.md)

---

# Ideas & Future Work

Potential directions. Not committed — just captured so they don't get lost.

## CI Pipeline
Automated builds on push. QEMU tests run automatically, hardware tests triggered manually. Could use GitHub Actions with self-hosted runners for hardware.

## ESP-IDF Crash Analysis
ESP-IDF has its own coredump format (different from Zephyr). Could extend `analyze_coredump` to detect and handle ESP32 core dumps, or add a separate `analyze_esp_coredump` tool.

## New Library Ideas
Candidates based on patterns that keep repeating:
- **BLE NUS abstraction** — Already exists in `ble_wifi_bridge`, could extract to a shared library
- **Logging configuration helper** — Standardize RTT vs UART vs both
- **OTA DFU shell commands** — MCUboot-based firmware update management via shell
