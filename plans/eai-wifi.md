# eai_wifi — Portable WiFi Connection Manager

Status: Complete
Created: 2026-02-16

## Problem

WiFi scan/connect was the second most expensive rewrite in the ESP-IDF port. Same operations, same callback patterns, same state — different platform APIs (`net_mgmt` vs `esp_wifi`). `eai_wifi` abstracts this so consumers call scan/connect/disconnect and the backend handles platform details.

## Approach

Three backends (Zephyr net_mgmt, ESP-IDF esp_wifi, POSIX stub) behind a single 8-function API. connect() takes raw bytes + lengths matching wifi_prov_cred structure. EVT_CONNECTED fires only after IP obtained. DHCP and power management handled internally per backend.

## Solution

- Public API: init, set_event_callback, scan, connect, disconnect, get_state, get_ip (8 functions)
- 4 states: DISCONNECTED, SCANNING, CONNECTING, CONNECTED
- 3 events: EVT_CONNECTED, EVT_DISCONNECTED, EVT_CONNECT_FAILED
- Unified scan delivery: on_result per AP, then on_done
- POSIX stub with 6 test helpers for injection
- 17 native tests, Zephyr build-only test on nrf7002dk

## Implementation Notes

- POSIX stub needed `#include <stdbool.h>` for native compilation (Zephyr headers include it implicitly).
- Zephyr build-only test needed `CONFIG_TEST_RANDOM_GENERATOR=y` — networking stack requires entropy, and without BT enabled, the nRF entropy driver doesn't get pulled in automatically.
- Zephyr build-only test also needed `CONFIG_NET_L2_ETHERNET=y`, `CONFIG_NET_MGMT_EVENT_INFO=y`, and `CONFIG_HEAP_MEM_POOL_SIZE=4096` beyond what was in the original plan.
- Board overlay for nrf7002dk copied from wifi_provision app: `CONFIG_WIFI_NRF70=y`, `CONFIG_WIFI_NM=y`, `CONFIG_WIFI_NM_WPA_SUPPLICANT=y` + net buffer counts.

### Files Created
- `lib/eai_wifi/include/eai_wifi/eai_wifi.h` — Public API
- `lib/eai_wifi/src/zephyr/wifi.c` — Zephyr net_mgmt backend
- `lib/eai_wifi/src/freertos/wifi.c` — ESP-IDF esp_wifi backend
- `lib/eai_wifi/src/posix/wifi.c` — POSIX stub backend
- `lib/eai_wifi/CMakeLists.txt`, `Kconfig`, `manifest.yml`, `zephyr/module.yml` — Build files
- `lib/eai_wifi/tests/native/` — 17 Unity tests
- `lib/eai_wifi/tests/` — Zephyr build-only test with board overlay
- `lib/eai_wifi/CLAUDE.md` — Usage documentation

### Files Modified
- `lib/CMakeLists.txt` — Added `add_subdirectory(eai_wifi)`
- `lib/Kconfig` — Added `rsource "eai_wifi/Kconfig"`
- `firmware/CLAUDE.md` — Added eai_wifi to library table

## Modifications

No deviations from original plan scope.
