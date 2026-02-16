# WiFi Provision on FreeRTOS (ESP-IDF)

Status: In-Progress (Phase 2-3 Complete, Phase 4 Pending)
Created: 2026-02-16

## Problem

We have a working WiFi provisioning system on Zephyr (`lib/wifi_prov/` + `apps/wifi_provision/`). Our OSAL (`lib/eai_osal/`) claims to enable multi-RTOS portability, but only has a Zephyr backend. We need to build the same WiFi provision app on ESP-IDF/FreeRTOS to:
1. Implement the FreeRTOS OSAL backend (Phase 1.5 from `plans/eai-osal.md`)
2. Discover what the OSAL doesn't cover (peripheral HALs, logging, settings)
3. Validate our code-sharing strategy across build systems
4. Get the same BLE provisioning + WiFi + TCP throughput working on ESP32 DevKitC

## Approach

Rename `zephyr-apps` → `firmware` to reflect multi-RTOS scope, then build an ESP-IDF project that shares portable code (state machine, message codec) and provides ESP-IDF implementations for platform-specific modules.

## Phases

- Phase 0: Rename zephyr-apps → firmware ✅
- Phase 1: OSAL FreeRTOS backend (all 9 primitives) ✅ — 44/44 tests on ESP32
- Phase 2: ESP-IDF WiFi Provision project ✅ — builds, boots, all features work
- Phase 3: Integration testing on ESP32 DevKitC ✅ — 6/6 integration tests pass
- Phase 4: Unit tests + documentation — pending

## Solution

ESP-IDF WiFi provisioning app at `firmware/esp-idf/wifi_provision/` shares portable code from `lib/wifi_prov/` (state machine, message codec) via ESP-IDF component CMakeLists.txt with shim headers for Zephyr logging macros. Platform-specific modules (BLE via NimBLE, WiFi via esp_wifi, credentials via NVS, orchestrator via OSAL work queues) are implemented in `components/wifi_prov_esp/`.

Integration test results (ESP32 DevKitC):
- BLE discovery, AP scan, WiFi provisioning (WPA3-SAE), TCP throughput (echo/upload/download), credential persistence across reboot, factory reset — all verified.
- TCP throughput: ~405 Kbps upload, ~30 Kbps download, ~47 Kbps echo (RSSI -83, weak signal)
- macOS Python tools work unchanged against ESP32 (same GATT protocol as Zephyr/nRF7002-DK)

## Implementation Notes

Key discoveries and fixes during implementation:
- **ESP32 StackType_t is uint8_t**: FreeRTOS `xTaskCreate` stack_depth is bytes on Xtensa. System work queue needed 4096 bytes (not 2048) for WiFi API calls.
- **WiFi power management**: `esp_wifi_set_ps(WIFI_PS_NONE)` required — modem sleep blocks incoming TCP/ping.
- **ESP-IDF scan results delivery**: Batched via `WIFI_EVENT_SCAN_DONE` + `esp_wifi_scan_get_ap_records()`, unlike Zephyr's per-result callbacks. Added `scan_done_callback` to fire `WIFI_PROV_EVT_SCAN_DONE`.
- **WiFi disconnect semantics**: `WIFI_EVENT_STA_DISCONNECTED` fires for both auth failure and real disconnect. Orchestrator checks current state to send `WIFI_FAILED` vs `WIFI_DISCONNECTED`.
- **CoreBluetooth GATT cache**: macOS caches GATT services aggressively. Rapid BLE reconnections fail — mitigated by ESP32 reset between connections or keeping single persistent connection.
- **bleak 2.1.1 API change**: `BLEDevice.rssi` removed. Use `discovered_devices_and_advertisement_data` for RSSI from `AdvertisementData`.
- **hw-test-runner factory reset**: Was sending 0x01 instead of protocol-required 0xFF.
