# wifi_prov Unification — Replace Platform Code with eai_* Libraries

Status: Complete
Created: 2026-02-16

## Problem

wifi_prov has 8 platform-specific files (4 Zephyr + 4 ESP-IDF) totaling ~1820 lines. We now have eai_* libraries that abstract all four concerns. Replace the duplicated code with 4 portable files.

## Approach

Replace platform-specific WiFi, BLE, credentials, and orchestrator code with eai_wifi, eai_ble, eai_settings, and eai_osal respectively. Also convert sm.c and msg.c to use eai_log/standard headers instead of Zephyr shim headers, enabling full shim removal.

## Solution

Replaced 8 platform-specific files (4 Zephyr + 4 ESP-IDF, ~1820 lines) with 4 portable files (~687 lines) using eai_* library APIs. All code now compiles identically on both platforms — the only platform-specific code is in the eai_* backends.

Key deliverables:
- 4 rewritten source files: wifi_prov.c, wifi_prov_ble.c, wifi_prov_wifi.c, wifi_prov_cred.c
- 2 updated source files: wifi_prov_sm.c, wifi_prov_msg.c (headers only)
- 4 new ESP-IDF component wrappers: eai_ble, eai_wifi, eai_settings, eai_log
- Deleted: wifi_prov_esp/ (4 ESP-IDF files), shim headers, wifi_prov_stub.c
- Updated: CMakeLists.txt, Kconfig, prj.conf, ESP-IDF test components

## Phase Tracking

### Phase 1: BLE + WiFi modules
- [x] Rewrite `wifi_prov_ble.c` using eai_ble declarative service
- [x] Rewrite `wifi_prov_wifi.c` using eai_wifi
- [x] Create ESP-IDF `eai_ble` component wrapper
- [x] Create ESP-IDF `eai_wifi` component wrapper

### Phase 2: Credentials + Orchestrator
- [x] Rewrite `wifi_prov_cred.c` using eai_settings
- [x] Unify `wifi_prov.c` orchestrator using eai_osal + eai_log
- [x] Create ESP-IDF `eai_settings` component wrapper
- [x] Create ESP-IDF `eai_log` component wrapper
- [x] Update `wifi_prov_sm.c` to use eai_log (replace Zephyr includes)
- [x] Update `wifi_prov_msg.c` to use standard headers (replace Zephyr kernel.h)
- [x] Delete `wifi_prov_stub.c`

### Phase 3: Build system + cleanup
- [x] Update `lib/wifi_prov/CMakeLists.txt` (new deps)
- [x] Update `lib/wifi_prov/Kconfig` (eai_* deps)
- [x] Remove `wifi_prov_esp` component directory
- [x] Remove shim headers from `wifi_prov_common`
- [x] Update `wifi_prov_common/CMakeLists.txt` to compile ALL portable sources
- [x] Update ESP-IDF test components (`wifi_prov_tests/components/`)
- [x] Update prj.conf for tests (added CONFIG_LOG, CONFIG_EAI_LOG, CONFIG_EAI_SETTINGS)

### Phase 4: Verify
- [x] Zephyr tests pass: 22/22 on qemu_cortex_m3 (Docker)
- [x] Full test suite passes: 73/73 tests (crash_log + eai_osal + wifi_prov + device_shell)
- [x] ESP-IDF app builds: wifi_provision builds for ESP32 (manual idf.py, MCP has Python env issue)
- [x] ESP-IDF tests pass: 22/22 on real ESP32 hardware (wifi_prov_tests flashed + monitored)

## Implementation Notes

### Deviations from original plan
1. **sm.c and msg.c updated** — Original plan said "keep unchanged." But removing shim headers required sm.c to use eai_log (instead of Zephyr LOG_*) and msg.c to use standard headers (instead of Zephyr kernel.h). Minimal changes — just includes and macro names.
2. **LOG_MODULE_REGISTER moved** — Was in wifi_prov_stub.c (sole purpose of that file). Now in wifi_prov_sm.c as `EAI_LOG_MODULE_REGISTER`. All other files use `EAI_LOG_MODULE_DECLARE`.
3. **Test prj.conf updated** — Added CONFIG_LOG=y, CONFIG_EAI_LOG=y, CONFIG_EAI_SETTINGS=y to satisfy new Kconfig dependency chain.
4. **errno.h missing** — wifi_prov_ble.c and wifi_prov_wifi.c used EINVAL/ENOTCONN without `#include <errno.h>`. Worked on Zephyr (pulled in transitively) but failed on ESP-IDF. Added explicit include.

### Build system notes
- Zephyr Kconfig: WIFI_PROV depends on EAI_LOG. WIFI_PROV_BLE depends on EAI_BLE. WIFI_PROV_WIFI depends on EAI_WIFI. WIFI_PROV_CRED depends on EAI_SETTINGS.
- ESP-IDF: wifi_prov_common now compiles all 6 source files and depends on eai_log, eai_ble, eai_wifi, eai_settings, eai_osal.
- ESP-IDF tests: wifi_prov_common compiles only sm.c, msg.c, cred.c. Removed wifi_prov_cred component (cred.c is now portable and in wifi_prov_common).
- Docker Makefile path was stale (`zephyr-apps` → should be `firmware`). Used direct Docker command for testing.

### ESP-IDF component wrappers
All follow the eai_osal pattern: `idf_component_register(SRCS "lib/<name>/src/freertos/<file>.c")` with `target_compile_definitions(PUBLIC CONFIG_EAI_<NAME>_BACKEND_FREERTOS=1)`.
- eai_log is header-only: uses `INTERFACE` instead of `PUBLIC` for compile definitions.
- eai_ble depends on `bt` (NimBLE) and `eai_osal`.
- eai_wifi depends on `esp_wifi`, `esp_event`, `esp_netif`.
- eai_settings depends on `nvs_flash`.

### ESP-IDF main component updated
Changed `main/CMakeLists.txt` from `REQUIRES wifi_prov_esp throughput_server` to `REQUIRES wifi_prov_common throughput_server`. No code changes needed in main.c.

## Key Design Decisions

1. **BLE**: Use `eai_ble_gatt_register()` declarative service. Single `on_write` callback dispatches by `char_index`. Read callback for status char fills current state + IP. Notify via `eai_ble_notify(char_index, data, len)`.

2. **WiFi**: Use eai_wifi's 3-event model (CONNECTED, DISCONNECTED, CONNECT_FAILED). Adopt scan_done callback from eai_wifi. Map eai_wifi_event to wifi_prov state machine events. Orchestrator checks current_state to differentiate FAILED vs DISCONNECTED.

3. **Credentials**: Use eai_settings_set/get/delete with "wifi_prov/" key prefix. Three keys: ssid, psk, sec. In-memory cache maintained for fast access.

4. **Orchestrator**: ESP-IDF version was the template (already uses eai_osal). Uses `#ifdef CONFIG_WIFI_PROV_AUTO_CONNECT` instead of `IS_ENABLED()`.

5. **sm.c/msg.c**: Updated to use eai_log and standard headers. Enables full shim removal.

## API Mapping Notes

### wifi_prov_ble.c
- `bt_enable()` → `eai_ble_init(cbs)`
- `BT_GATT_SERVICE_DEFINE()` → `eai_ble_gatt_register(svc)` (runtime, not static)
- `bt_le_adv_start()` → `eai_ble_adv_start(name)`
- `bt_gatt_notify(conn, attrs[N], ...)` → `eai_ble_notify(char_index, ...)`
- Write handlers: `ssize_t fn(bt_conn*, ...)` → `void fn(uint8_t idx, uint8_t* data, uint16_t len)`
- Read handler: `ssize_t fn(bt_conn*, ...)` → `int fn(uint8_t idx, uint8_t* buf, uint16_t* len)`
- Connection callbacks: `BT_CONN_CB_DEFINE` → `eai_ble_callbacks.on_connect/on_disconnect`

### wifi_prov_wifi.c
- `wifi_prov_wifi_init(state_cb)` → `eai_wifi_init()` + `eai_wifi_set_event_callback(cb)`
- `wifi_prov_wifi_scan(result_cb)` → `eai_wifi_scan(on_result, on_done)` (adds done callback)
- `wifi_prov_wifi_connect(cred)` → `eai_wifi_connect(ssid, len, psk, len, sec)` (unpacked args)
- Security mapping: `WIFI_PROV_SEC_*` → `EAI_WIFI_SEC_*`

### wifi_prov_cred.c
- `settings_save_one("wifi_prov/ssid", ...)` → `eai_settings_set("wifi_prov/ssid", ...)`
- `settings_load_subtree("wifi_prov")` → `eai_settings_get("wifi_prov/ssid", ...)`
- `SETTINGS_STATIC_HANDLER_DEFINE` → not needed (eai_settings handles registration)

### wifi_prov.c (orchestrator)
- `k_work` → `eai_osal_work_t`
- `k_work_schedule(work, K_SECONDS(2))` → `eai_osal_dwork_submit(work, 2000)`
- `settings_subsys_init()` → `eai_settings_init()`

## ESP-IDF Component Wrapper Pattern

Follow `eai_osal/CMakeLists.txt`:
```cmake
set(ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../lib/<name>")
idf_component_register(
    SRCS "${ROOT}/src/freertos/<file>.c"
    INCLUDE_DIRS "${ROOT}/include"
    REQUIRES <deps>
)
target_compile_definitions(${COMPONENT_LIB} PUBLIC CONFIG_EAI_<NAME>_BACKEND_FREERTOS=1)
```

## Files Changed

### Rewritten
- `firmware/lib/wifi_prov/src/wifi_prov.c` — unified orchestrator
- `firmware/lib/wifi_prov/src/wifi_prov_ble.c` — eai_ble declarative
- `firmware/lib/wifi_prov/src/wifi_prov_wifi.c` — eai_wifi wrapper
- `firmware/lib/wifi_prov/src/wifi_prov_cred.c` — eai_settings wrapper

### Updated (headers only)
- `firmware/lib/wifi_prov/src/wifi_prov_sm.c` — eai_log
- `firmware/lib/wifi_prov/src/wifi_prov_msg.c` — standard headers

### Created
- `firmware/esp-idf/wifi_provision/components/eai_ble/CMakeLists.txt`
- `firmware/esp-idf/wifi_provision/components/eai_wifi/CMakeLists.txt`
- `firmware/esp-idf/wifi_provision/components/eai_settings/CMakeLists.txt`
- `firmware/esp-idf/wifi_provision/components/eai_log/CMakeLists.txt`
- `firmware/esp-idf/wifi_prov_tests/components/eai_settings/CMakeLists.txt`
- `firmware/esp-idf/wifi_prov_tests/components/eai_log/CMakeLists.txt`

### Deleted
- `firmware/esp-idf/wifi_provision/components/wifi_prov_esp/` (entire directory)
- `firmware/esp-idf/wifi_provision/components/wifi_prov_common/shim/` (entire directory)
- `firmware/esp-idf/wifi_prov_tests/components/wifi_prov_common/shim/` (entire directory)
- `firmware/esp-idf/wifi_prov_tests/components/wifi_prov_cred/` (entire directory)
- `firmware/lib/wifi_prov/src/wifi_prov_stub.c`

### Modified
- `firmware/lib/wifi_prov/CMakeLists.txt` — removed stub.c
- `firmware/lib/wifi_prov/Kconfig` — eai_* dependencies
- `firmware/lib/wifi_prov/tests/prj.conf` — added LOG, EAI_LOG, EAI_SETTINGS
- `firmware/esp-idf/wifi_provision/components/wifi_prov_common/CMakeLists.txt` — all 6 sources
- `firmware/esp-idf/wifi_provision/main/CMakeLists.txt` — wifi_prov_common (was wifi_prov_esp)
- `firmware/esp-idf/wifi_prov_tests/components/wifi_prov_common/CMakeLists.txt` — sm+msg+cred
- `firmware/esp-idf/wifi_prov_tests/main/CMakeLists.txt` — removed wifi_prov_cred dep
