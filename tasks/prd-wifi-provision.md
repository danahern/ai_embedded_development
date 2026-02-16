# PRD: WiFi Provisioning App

## Overview

Build a cross-platform WiFi provisioning system: a Zephyr shared library (`lib/wifi_prov/`), a thin application (`apps/wifi_provision/`), and macOS Python test tools. A macOS device discovers the embedded device over BLE, triggers WiFi AP scanning, sends credentials, and the device connects to WiFi. Once on WiFi, the device runs a TCP throughput server.

Target boards: `nrf7002dk/nrf5340/cpuapp` and `esp32_devkitc/esp32/procpu`. Unit tests on `qemu_cortex_m3`.

## Workspace Context

This is a Zephyr workspace managed by `west`. Key paths (all relative to workspace root):

| Path | Purpose |
|------|---------|
| `zephyr-apps/lib/` | Shared libraries (crash_log, device_shell, eai_osal) |
| `zephyr-apps/apps/` | Applications |
| `test-tools/` | Python test utilities |

**Build system:** Use the `zephyr-build` MCP tools — NOT raw `west` CLI commands.
- `zephyr-build.build(app="wifi_provision", board="nrf7002dk/nrf5340/cpuapp")` to build the app
- `zephyr-build.build(app="wifi_prov_tests", board="qemu_cortex_m3")` to build tests (test app name TBD based on how twister discovers it)
- `zephyr-build.run_tests(board="qemu_cortex_m3", path="lib/wifi_prov")` to run unit tests

**CRITICAL: Module registration.** For the library to be found by apps, it must be registered as a Zephyr module. The workspace `zephyr-apps/zephyr/module.yml` auto-discovers libraries under `lib/`. Check `zephyr-apps/zephyr/module.yml` for the discovery mechanism — if it doesn't auto-discover, add `wifi_prov` explicitly.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  macOS Tools                     │
│  wifi_provision_tool.py ──BLE──┐                │
│  throughput_test.py ───TCP─────┤                │
└────────────────────────────────┤────────────────┘
                                 │
┌────────────────────────────────┤────────────────┐
│  apps/wifi_provision/          │   (thin app)   │
│  ┌─────────────────┐  ┌───────┴──────┐         │
│  │ throughput_server│  │    main.c    │         │
│  └────────┬────────┘  └───────┬──────┘         │
│           │                   │                  │
├───────────┼───────────────────┼──────────────────┤
│  lib/wifi_prov/               │   (library)     │
│  ┌──────────┐ ┌──────────┐ ┌─┴────────┐        │
│  │ wifi_prov│ │wifi_prov │ │wifi_prov  │        │
│  │  _ble.c  │ │ _wifi.c  │ │  _cred.c  │        │
│  └────┬─────┘ └────┬─────┘ └─────┬────┘        │
│       │             │             │              │
│       └──────┬──────┘             │              │
│         ┌────┴─────┐        ┌────┴─────┐        │
│         │wifi_prov │        │wifi_prov  │        │
│         │  _sm.c   │        │  _msg.c   │        │
│         └──────────┘        └──────────┘        │
└─────────────────────────────────────────────────┘
```

## Reference Patterns — READ THESE FILES

Before writing code, read these existing files to match the project's conventions:

1. **Library structure:** `zephyr-apps/lib/crash_log/CMakeLists.txt`, `Kconfig`, `zephyr/module.yml`, `manifest.yml`
2. **Library API style:** `zephyr-apps/lib/crash_log/include/crash_log.h`
3. **Library tests:** `zephyr-apps/lib/crash_log/tests/` (all files)
4. **WiFi patterns:** `zephyr-apps/apps/ble_wifi_bridge/src/wifi_manager.c` and `.h`
5. **BLE patterns:** `zephyr-apps/apps/ble_wifi_bridge/src/ble_nus.c` and `.h`
6. **App Kconfig baseline:** `zephyr-apps/apps/ble_wifi_bridge/prj.conf`
7. **App CMakeLists:** `zephyr-apps/apps/ble_wifi_bridge/CMakeLists.txt`
8. **Module registration:** `zephyr-apps/zephyr/module.yml`
9. **Existing Python tools:** `test-tools/ble/` directory for bleak usage patterns

## Technical Reference

### BLE GATT Service

Custom service UUID base: `a0e4f2b0-XXXX-4c9a-b000-d0e6a7b8c9d0`

| Characteristic | UUID (XXXX) | Properties | Format |
|---------------|-------------|------------|--------|
| Scan Trigger | 0002 | Write | `[0x01]` to start scan |
| Scan Results | 0003 | Notify | `[ssid_len:1][ssid:1-32][rssi:1,signed][security:1][channel:1]` |
| Credentials | 0004 | Write | `[ssid_len:1][ssid:1-32][psk_len:1][psk:0-64][security:1]` |
| Status | 0005 | Read, Notify | `[state:1][ip_addr:4]` (0.0.0.0 if not connected) |
| Factory Reset | 0006 | Write | `[0xFF]` to trigger |

### State Machine

```
IDLE ──(scan_trigger)──→ SCANNING
SCANNING ──(scan_done)──→ SCAN_COMPLETE
SCAN_COMPLETE ──(credentials_rx)──→ PROVISIONING
PROVISIONING ──(wifi_connecting)──→ CONNECTING
CONNECTING ──(wifi_connected)──→ CONNECTED
CONNECTING ──(wifi_failed)──→ IDLE
CONNECTED ──(wifi_disconnected)──→ IDLE
ANY ──(factory_reset)──→ IDLE
```

State values: `IDLE=0, SCANNING=1, SCAN_COMPLETE=2, PROVISIONING=3, CONNECTING=4, CONNECTED=5`

### Credential Storage (Zephyr Settings)

Keys under `wifi_prov/`:
- `wifi_prov/ssid` — SSID string (max 32 bytes)
- `wifi_prov/psk` — Password string (max 64 bytes)
- `wifi_prov/sec` — Security type (uint8_t): 0=NONE, 1=WPA_PSK, 2=WPA2_PSK, 3=WPA2_PSK_SHA256, 4=WPA3_SAE

### Key Kconfig Options

```kconfig
config WIFI_PROV
    bool "WiFi provisioning library"

config WIFI_PROV_BLE
    bool "BLE GATT service for WiFi provisioning"
    depends on WIFI_PROV && BT

config WIFI_PROV_WIFI
    bool "WiFi manager (scan/connect)"
    depends on WIFI_PROV && WIFI

config WIFI_PROV_CRED
    bool "Credential persistence"
    depends on WIFI_PROV && SETTINGS
    default y if WIFI_PROV

config WIFI_PROV_AUTO_CONNECT
    bool "Auto-connect on boot from stored credentials"
    depends on WIFI_PROV_WIFI && WIFI_PROV_CRED
    default y
```

### TCP Throughput Server

- Listens on port 5001
- Protocol: first byte is command
  - `0x01` = echo mode (bidirectional): client sends data, server echoes back
  - `0x02` = sink mode (upload test): client sends, server discards, reports byte count
  - `0x03` = source mode (download test): server sends continuous data to client
- After command byte, remaining data is payload
- Server logs throughput stats via RTT every second

---

## User Stories

### Phase 1: Library Scaffold and Core Logic

These modules have NO hardware dependencies and are fully testable on QEMU.

---

#### US-001: Create wifi_prov library directory structure and build system

**As a** developer, **I need** the library scaffold in place **so that** subsequent stories can add implementation files incrementally.

**Files to create:**
- `zephyr-apps/lib/wifi_prov/CMakeLists.txt`
- `zephyr-apps/lib/wifi_prov/Kconfig`
- `zephyr-apps/lib/wifi_prov/zephyr/module.yml`
- `zephyr-apps/lib/wifi_prov/manifest.yml`
- `zephyr-apps/lib/wifi_prov/include/wifi_prov/wifi_prov.h` — Public API header (function declarations, no implementations yet)
- `zephyr-apps/lib/wifi_prov/include/wifi_prov/wifi_prov_msg.h` — Message type definitions and encode/decode declarations
- `zephyr-apps/lib/wifi_prov/include/wifi_prov/wifi_prov_types.h` — Shared types (state enum, credential struct, scan result struct)
- `zephyr-apps/lib/wifi_prov/src/wifi_prov_stub.c` — Minimal stub so it compiles (just a log message)

**Patterns to follow:**
- Read `zephyr-apps/lib/crash_log/CMakeLists.txt` and match the `zephyr_library_named()` pattern
- Read `zephyr-apps/lib/crash_log/Kconfig` and match the config hierarchy
- Read `zephyr-apps/lib/crash_log/zephyr/module.yml` — use same format
- Use `zephyr_include_directories_ifdef()` to expose `include/` directory
- Headers use `#include <wifi_prov/wifi_prov.h>` style (directory prefix in include path)

**Acceptance criteria:**
- [ ] All files listed above exist
- [ ] `zephyr-build.build(app="hello_world", board="qemu_cortex_m3", extra_args="-DCONFIG_WIFI_PROV=y")` succeeds — library is discoverable as a Zephyr module (NOTE: if module discovery doesn't work this way, create a minimal test app instead)
- [ ] Kconfig defines `WIFI_PROV`, `WIFI_PROV_BLE`, `WIFI_PROV_WIFI`, `WIFI_PROV_CRED` options
- [ ] Public headers define the state enum (`WIFI_PROV_STATE_IDLE` through `WIFI_PROV_STATE_CONNECTED`), credential struct, and scan result struct

---

#### US-002: Implement credential store using Zephyr Settings

**As a** device, **I need** to persist WiFi credentials across reboots **so that** I can auto-reconnect without re-provisioning.

**Files to create/modify:**
- Create `zephyr-apps/lib/wifi_prov/src/wifi_prov_cred.c`
- Update `CMakeLists.txt` to include this source under `CONFIG_WIFI_PROV_CRED`

**API (in wifi_prov.h or a new wifi_prov_cred.h):**
```c
int wifi_prov_cred_store(const struct wifi_prov_cred *cred);
int wifi_prov_cred_load(struct wifi_prov_cred *cred);
int wifi_prov_cred_erase(void);
bool wifi_prov_cred_exists(void);
```

**Implementation notes:**
- Use `settings_save_one()` / `settings_load_subtree()` with keys `wifi_prov/ssid`, `wifi_prov/psk`, `wifi_prov/sec`
- Register a settings handler via `SETTINGS_STATIC_HANDLER_DEFINE()`
- `wifi_prov_cred_exists()` checks if SSID is non-empty after loading
- All functions return 0 on success, negative errno on failure

**Acceptance criteria:**
- [ ] `wifi_prov_cred.c` compiles as part of the library
- [ ] Uses Zephyr Settings API (not raw flash or NVS directly)
- [ ] Store/load/erase/exists functions are implemented
- [ ] Library builds for `qemu_cortex_m3` with `CONFIG_WIFI_PROV=y CONFIG_WIFI_PROV_CRED=y CONFIG_SETTINGS=y`

---

#### US-003: Implement protocol message encode/decode

**As a** developer, **I need** structured message serialization **so that** BLE characteristics can transmit structured data reliably.

**Files to create/modify:**
- Create `zephyr-apps/lib/wifi_prov/src/wifi_prov_msg.c`
- Update `CMakeLists.txt` to include this source under `CONFIG_WIFI_PROV`

**API (in wifi_prov_msg.h):**
```c
/* Encode scan result into buffer. Returns bytes written, or negative errno. */
int wifi_prov_msg_encode_scan_result(const struct wifi_prov_scan_result *result,
                                     uint8_t *buf, size_t buf_size);

/* Decode scan result from buffer. Returns 0 on success. */
int wifi_prov_msg_decode_scan_result(const uint8_t *buf, size_t len,
                                     struct wifi_prov_scan_result *result);

/* Decode credentials from buffer. Returns 0 on success. */
int wifi_prov_msg_decode_credentials(const uint8_t *buf, size_t len,
                                      struct wifi_prov_cred *cred);

/* Encode credentials into buffer. Returns bytes written, or negative errno. */
int wifi_prov_msg_encode_credentials(const struct wifi_prov_cred *cred,
                                      uint8_t *buf, size_t buf_size);

/* Encode status into buffer. Returns bytes written (always 5). */
int wifi_prov_msg_encode_status(enum wifi_prov_state state,
                                const uint8_t ip_addr[4],
                                uint8_t *buf, size_t buf_size);

/* Decode status from buffer. */
int wifi_prov_msg_decode_status(const uint8_t *buf, size_t len,
                                enum wifi_prov_state *state,
                                uint8_t ip_addr[4]);
```

**Wire format:** See Technical Reference section above for byte layouts.

**Acceptance criteria:**
- [ ] All encode/decode functions implemented
- [ ] Handles edge cases: empty SSID, max-length SSID (32 bytes), empty PSK, max-length PSK (64 bytes)
- [ ] Returns `-EINVAL` for malformed input (truncated, invalid lengths)
- [ ] Returns `-ENOBUFS` when output buffer is too small
- [ ] Library builds for `qemu_cortex_m3`

---

#### US-004: Implement provisioning state machine

**As a** developer, **I need** a state machine **so that** the provisioning flow is predictable and testable.

**Files to create/modify:**
- Create `zephyr-apps/lib/wifi_prov/src/wifi_prov_sm.c`
- Update `CMakeLists.txt`

**API:**
```c
/* Event types that drive state transitions */
enum wifi_prov_event {
    WIFI_PROV_EVT_SCAN_TRIGGER,
    WIFI_PROV_EVT_SCAN_DONE,
    WIFI_PROV_EVT_CREDENTIALS_RX,
    WIFI_PROV_EVT_WIFI_CONNECTING,
    WIFI_PROV_EVT_WIFI_CONNECTED,
    WIFI_PROV_EVT_WIFI_FAILED,
    WIFI_PROV_EVT_WIFI_DISCONNECTED,
    WIFI_PROV_EVT_FACTORY_RESET,
};

/* Callback for state changes */
typedef void (*wifi_prov_state_cb_t)(enum wifi_prov_state old_state,
                                     enum wifi_prov_state new_state);

void wifi_prov_sm_init(wifi_prov_state_cb_t callback);
enum wifi_prov_state wifi_prov_sm_get_state(void);
int wifi_prov_sm_process_event(enum wifi_prov_event event);
```

**Transition rules:** See state machine diagram in Technical Reference.
- `wifi_prov_sm_process_event()` returns 0 on valid transition, `-EPERM` on invalid transition
- Factory reset always transitions to IDLE regardless of current state

**Acceptance criteria:**
- [ ] All valid transitions from the state diagram work correctly
- [ ] Invalid transitions return `-EPERM` and don't change state
- [ ] Factory reset works from every state
- [ ] State change callback fires on every transition
- [ ] Library builds for `qemu_cortex_m3`

---

### Phase 2: Unit Tests

---

#### US-005: Create test infrastructure and credential store tests

**As a** developer, **I need** unit tests **so that** the core logic is verified without hardware.

**Files to create:**
- `zephyr-apps/lib/wifi_prov/tests/CMakeLists.txt`
- `zephyr-apps/lib/wifi_prov/tests/prj.conf`
- `zephyr-apps/lib/wifi_prov/tests/testcase.yaml`
- `zephyr-apps/lib/wifi_prov/tests/src/main.c` — test runner
- `zephyr-apps/lib/wifi_prov/tests/src/test_cred.c` — credential store tests

**Pattern to follow:** Read `zephyr-apps/lib/crash_log/tests/` for the exact structure.

**Test cases for credentials:**
- `test_no_cred_on_clean_boot` — `wifi_prov_cred_exists()` returns false
- `test_store_and_load` — store credentials, load them back, values match
- `test_erase` — store then erase, `wifi_prov_cred_exists()` returns false
- `test_load_when_empty` — `wifi_prov_cred_load()` returns error or zero-filled struct
- `test_overwrite` — store twice, load returns second set

**prj.conf must include:**
```
CONFIG_ZTEST=y
CONFIG_SETTINGS=y
CONFIG_SETTINGS_RUNTIME=y
CONFIG_WIFI_PROV=y
CONFIG_WIFI_PROV_CRED=y
```

**testcase.yaml:**
```yaml
common:
  tags:
    - wifi_prov
tests:
  libraries.wifi_prov:
    integration_platforms:
      - qemu_cortex_m3
```

**Acceptance criteria:**
- [ ] `zephyr-build.run_tests(board="qemu_cortex_m3", path="lib/wifi_prov")` passes
- [ ] At least 5 test cases for credential store
- [ ] Tests use `zassert_*` macros from ztest

---

#### US-006: Add protocol message encode/decode tests

**As a** developer, **I need** message serialization tests **so that** BLE communication is reliable.

**Files to create/modify:**
- Create `zephyr-apps/lib/wifi_prov/tests/src/test_msg.c`
- Update `main.c` to include the new test suite

**Test cases:**
- `test_encode_decode_scan_result` — round-trip a scan result
- `test_encode_decode_credentials` — round-trip credentials
- `test_encode_decode_status` — round-trip status with IP
- `test_decode_truncated_scan_result` — returns `-EINVAL`
- `test_decode_truncated_credentials` — returns `-EINVAL`
- `test_encode_buffer_too_small` — returns `-ENOBUFS`
- `test_max_length_ssid` — 32-byte SSID round-trips correctly
- `test_empty_psk` — open network (no password) round-trips correctly

**Acceptance criteria:**
- [ ] `zephyr-build.run_tests(board="qemu_cortex_m3", path="lib/wifi_prov")` passes
- [ ] At least 6 test cases for message encode/decode
- [ ] Tests cover both success and error paths

---

#### US-007: Add state machine transition tests

**As a** developer, **I need** state machine tests **so that** the provisioning flow is correct.

**Files to create/modify:**
- Create `zephyr-apps/lib/wifi_prov/tests/src/test_sm.c`
- Update `main.c` to include the new test suite

**Test cases:**
- `test_initial_state_is_idle` — state machine starts in IDLE
- `test_scan_flow` — IDLE → SCANNING → SCAN_COMPLETE
- `test_provision_flow` — SCAN_COMPLETE → PROVISIONING → CONNECTING → CONNECTED
- `test_connection_failure` — CONNECTING → IDLE on WIFI_FAILED
- `test_disconnect` — CONNECTED → IDLE on WIFI_DISCONNECTED
- `test_factory_reset_from_connected` — CONNECTED → IDLE on FACTORY_RESET
- `test_factory_reset_from_scanning` — SCANNING → IDLE on FACTORY_RESET
- `test_invalid_transition` — IDLE + SCAN_DONE returns `-EPERM`, state unchanged
- `test_state_change_callback` — callback fires with correct old/new states

**Acceptance criteria:**
- [ ] `zephyr-build.run_tests(board="qemu_cortex_m3", path="lib/wifi_prov")` passes
- [ ] At least 8 test cases for state machine
- [ ] Tests verify both valid and invalid transitions

---

### Phase 3: BLE and WiFi Integration

These modules depend on BLE/WiFi hardware. Acceptance is "builds successfully" — hardware testing happens post-Ralph.

---

#### US-008: Implement custom BLE GATT service

**As a** device, **I need** a BLE GATT service **so that** a macOS app can interact with the provisioning system.

**Files to create/modify:**
- Create `zephyr-apps/lib/wifi_prov/src/wifi_prov_ble.c`
- Update `CMakeLists.txt` to include under `CONFIG_WIFI_PROV_BLE`

**Implementation:**
- Define custom service UUID: `a0e4f2b0-0001-4c9a-b000-d0e6a7b8c9d0`
- Define 5 characteristics (see Technical Reference for UUIDs and properties)
- Use `BT_GATT_SERVICE_DEFINE()` macro for static service registration
- Write handlers decode messages via `wifi_prov_msg_*` functions
- Notify handlers encode messages via `wifi_prov_msg_*` functions
- Provide functions:
  ```c
  int wifi_prov_ble_init(void);
  int wifi_prov_ble_start_advertising(void);
  int wifi_prov_ble_notify_scan_result(const struct wifi_prov_scan_result *result);
  int wifi_prov_ble_notify_status(enum wifi_prov_state state, const uint8_t ip[4]);
  ```

**Pattern to follow:** Read `zephyr-apps/apps/ble_wifi_bridge/src/ble_nus.c` for BLE init, advertising, connection callbacks. But use `BT_GATT_SERVICE_DEFINE()` instead of NUS — this is a custom service.

**Acceptance criteria:**
- [ ] Compiles with `CONFIG_WIFI_PROV_BLE=y CONFIG_BT=y CONFIG_BT_PERIPHERAL=y`
- [ ] Uses `BT_GATT_SERVICE_DEFINE()` with custom UUIDs
- [ ] All 5 characteristics defined with correct properties (write/read/notify)
- [ ] `zephyr-build.build(app="hello_world", board="nrf7002dk/nrf5340/cpuapp", extra_args="-DCONFIG_WIFI_PROV=y -DCONFIG_WIFI_PROV_BLE=y")` succeeds — or build a minimal test app if needed

---

#### US-009: Implement WiFi manager (scan, connect, IP query)

**As a** device, **I need** WiFi scanning and connection **so that** provisioned credentials can be used to join a network.

**Files to create/modify:**
- Create `zephyr-apps/lib/wifi_prov/src/wifi_prov_wifi.c`
- Update `CMakeLists.txt` to include under `CONFIG_WIFI_PROV_WIFI`

**API:**
```c
typedef void (*wifi_prov_scan_result_cb_t)(const struct wifi_prov_scan_result *result);
typedef void (*wifi_prov_wifi_state_cb_t)(bool connected);

int wifi_prov_wifi_init(wifi_prov_wifi_state_cb_t state_cb);
int wifi_prov_wifi_scan(wifi_prov_scan_result_cb_t result_cb);
int wifi_prov_wifi_connect(const struct wifi_prov_cred *cred);
int wifi_prov_wifi_disconnect(void);
int wifi_prov_wifi_get_ip(uint8_t ip_addr[4]);
bool wifi_prov_wifi_is_connected(void);
```

**Pattern to follow:** Read `zephyr-apps/apps/ble_wifi_bridge/src/wifi_manager.c` — reuse the `net_mgmt` event callback pattern, WiFi connect params, and DHCP handling. Key differences:
- Add scan support via `NET_REQUEST_WIFI_SCAN` and `NET_EVENT_WIFI_SCAN_RESULT`
- Accept runtime credentials (not compile-time Kconfig)
- Extract IP address programmatically

**Acceptance criteria:**
- [ ] Compiles with `CONFIG_WIFI_PROV_WIFI=y CONFIG_WIFI=y CONFIG_NETWORKING=y`
- [ ] Scan, connect, disconnect, get_ip, is_connected functions implemented
- [ ] WiFi scan uses `net_mgmt(NET_REQUEST_WIFI_SCAN, ...)` with `NET_EVENT_WIFI_SCAN_RESULT` callback
- [ ] WiFi connect uses `net_mgmt(NET_REQUEST_WIFI_CONNECT, ...)` with runtime credentials
- [ ] `zephyr-build.build(app="hello_world", board="nrf7002dk/nrf5340/cpuapp", extra_args="-DCONFIG_WIFI_PROV=y -DCONFIG_WIFI_PROV_WIFI=y")` succeeds — or build a minimal test app if needed

---

#### US-010: Wire library modules together — main entry point

**As a** developer, **I need** a single init function **so that** apps can use the library with one call.

**Files to create/modify:**
- Create `zephyr-apps/lib/wifi_prov/src/wifi_prov.c`
- Update `CMakeLists.txt`
- Finalize `wifi_prov.h` public API

**Top-level API:**
```c
/* Initialize the entire wifi_prov subsystem */
int wifi_prov_init(void);

/* Start BLE advertising (call after init) */
int wifi_prov_start(void);

/* Factory reset: erase credentials, disconnect, return to advertising */
int wifi_prov_factory_reset(void);

/* Get current state */
enum wifi_prov_state wifi_prov_get_state(void);

/* Get IP address (valid only in CONNECTED state) */
int wifi_prov_get_ip(uint8_t ip_addr[4]);
```

**Implementation:**
- `wifi_prov_init()`: init settings, load credentials, init state machine, init BLE, init WiFi
- If stored credentials exist and `CONFIG_WIFI_PROV_AUTO_CONNECT=y`, auto-connect on init
- BLE write handlers: scan trigger → `wifi_prov_wifi_scan()`, credentials → store + connect, factory reset → erase + disconnect
- WiFi callbacks: scan results → BLE notify, connect/disconnect → state machine → BLE notify status
- Factory reset: erase creds, disconnect WiFi, reset state to IDLE

**Acceptance criteria:**
- [ ] Single `wifi_prov_init()` + `wifi_prov_start()` is all an app needs
- [ ] Auto-connect from stored credentials works (code path exists, can't test without hardware)
- [ ] Factory reset erases credentials, disconnects, resets state
- [ ] BLE and WiFi events flow through the state machine correctly
- [ ] Library builds for `nrf7002dk/nrf5340/cpuapp`

---

### Phase 4: Application

---

#### US-011: Create wifi_provision app with board configurations

**As a** developer, **I need** a thin application **so that** I can flash the provisioning firmware to real hardware.

**Files to create:**
- `zephyr-apps/apps/wifi_provision/CMakeLists.txt`
- `zephyr-apps/apps/wifi_provision/prj.conf`
- `zephyr-apps/apps/wifi_provision/Kconfig`
- `zephyr-apps/apps/wifi_provision/src/main.c`
- `zephyr-apps/apps/wifi_provision/boards/nrf7002dk_nrf5340_cpuapp.conf` (board-specific Kconfig)
- `zephyr-apps/apps/wifi_provision/boards/esp32_devkitc_esp32_procpu.conf` (board-specific Kconfig)

**main.c should be minimal:**
```c
#include <wifi_prov/wifi_prov.h>

LOG_MODULE_REGISTER(main, LOG_LEVEL_INF);

int main(void) {
    LOG_INF("WiFi Provision app starting");

    int ret = wifi_prov_init();
    if (ret) {
        LOG_ERR("wifi_prov_init failed: %d", ret);
        return ret;
    }

    ret = wifi_prov_start();
    if (ret) {
        LOG_ERR("wifi_prov_start failed: %d", ret);
        return ret;
    }

    LOG_INF("WiFi Provision ready — advertising over BLE");
    return 0;
}
```

**prj.conf must include:** BLE, WiFi, networking, settings, logging, wifi_prov library enables. Reference `zephyr-apps/apps/ble_wifi_bridge/prj.conf` for the networking/WiFi/BLE baseline.

**Board-specific configs:**
- nRF7002-DK: May need `CONFIG_WIFI_NRF700X=y`, WPA supplicant configs, nRF5340 network core
- ESP32: `CONFIG_ESP32_USE_UNSUPPORTED_REVISION=y`, ESP WiFi driver configs

**Acceptance criteria:**
- [ ] `zephyr-build.build(app="wifi_provision", board="nrf7002dk/nrf5340/cpuapp")` succeeds
- [ ] `zephyr-build.build(app="wifi_provision", board="esp32_devkitc/esp32/procpu")` succeeds
- [ ] `main.c` is under 30 lines (thin app pattern)
- [ ] Board-specific configs exist for both boards

---

#### US-012: Add TCP throughput server

**As a** tester, **I need** a TCP throughput server **so that** I can measure WiFi performance after provisioning.

**Files to create/modify:**
- Create `zephyr-apps/apps/wifi_provision/src/throughput_server.c`
- Create `zephyr-apps/apps/wifi_provision/src/throughput_server.h`
- Update `CMakeLists.txt` and `main.c` to include and start the server

**Implementation:**
- Listens on configurable port (Kconfig `CONFIG_THROUGHPUT_PORT`, default 5001)
- Runs in its own thread (`K_THREAD_DEFINE`)
- Protocol: first byte = mode (echo=0x01, sink=0x02, source=0x03)
- Echo mode: read data, write it back
- Sink mode: read and discard, count bytes
- Source mode: write continuous 1KB blocks
- Log throughput every second via `LOG_INF`
- Server only starts when WiFi is connected (check state)
- Uses Zephyr POSIX socket API (`socket`, `bind`, `listen`, `accept`, `recv`, `send`)

**Acceptance criteria:**
- [ ] Throughput server compiles as part of the app
- [ ] Supports echo, sink, and source modes
- [ ] Runs in its own thread, doesn't block main
- [ ] `zephyr-build.build(app="wifi_provision", board="nrf7002dk/nrf5340/cpuapp")` succeeds

---

### Phase 5: macOS Python Tools

---

#### US-013: BLE WiFi provisioning tool

**As a** tester, **I need** a macOS BLE client **so that** I can provision WiFi credentials from my laptop.

**Files to create:**
- `test-tools/wifi_provision_tool.py`

**Implementation:**
- Uses `bleak` for BLE (already used in `test-tools/ble/`)
- CLI via `argparse` with subcommands:
  - `discover` — scan for devices advertising the WiFi Prov service UUID
  - `scan-aps --device <addr>` — connect, trigger AP scan, print results
  - `provision --device <addr> --ssid <ssid> --password <psk> --security <type>` — send credentials
  - `status --device <addr>` — read current state and IP address
  - `factory-reset --device <addr>` — trigger factory reset
- Uses the custom GATT UUIDs defined in Technical Reference
- Decodes messages using the same wire format as the firmware
- Async operation via `asyncio`

**Acceptance criteria:**
- [ ] `python3 test-tools/wifi_provision_tool.py --help` runs without error
- [ ] All 5 subcommands are implemented (discover, scan-aps, provision, status, factory-reset)
- [ ] Uses `bleak` for BLE communication
- [ ] Correctly encodes/decodes the wire format from Technical Reference
- [ ] Has proper error handling for BLE connection failures

---

#### US-014: TCP throughput test tool

**As a** tester, **I need** a throughput measurement tool **so that** I can benchmark WiFi performance.

**Files to create:**
- `test-tools/throughput_test.py`

**Implementation:**
- CLI via `argparse`:
  - `--host <ip>` — device IP (from provisioning tool's `status` command)
  - `--port <port>` — default 5001
  - `--mode <upload|download|bidirectional>` — test type
  - `--duration <seconds>` — test length (default 10)
  - `--block-size <bytes>` — default 1024
- Sends mode byte first (0x01=echo, 0x02=sink, 0x03=source) matching server protocol
- Per-second stats: bytes transferred, throughput (KB/s), cumulative
- Final summary: total bytes, average throughput, min/max/avg per-second rates
- Jitter: standard deviation of per-second throughput
- Uses standard library `socket` module (no external deps beyond Python stdlib)

**Acceptance criteria:**
- [ ] `python3 test-tools/throughput_test.py --help` runs without error
- [ ] Supports upload, download, and bidirectional modes
- [ ] Reports per-second stats during test
- [ ] Reports final summary with throughput, jitter
- [ ] Uses only Python standard library (no pip install needed)

---

### Phase 6: Documentation

---

#### US-015: Library and app documentation

**As a** developer, **I need** documentation **so that** I can understand and maintain the WiFi provisioning system.

**Files to create:**
- `zephyr-apps/lib/wifi_prov/CLAUDE.md`
- `zephyr-apps/apps/wifi_provision/README.md`

**`lib/wifi_prov/CLAUDE.md` must include:**
- What the library does
- Architecture (module diagram)
- Public API reference (all functions with brief descriptions)
- Kconfig options table
- BLE GATT service UUID table
- Wire format reference
- State machine diagram
- How to include in an app
- Testing instructions

**`apps/wifi_provision/README.md` must include:**
- What the app does
- Supported boards
- Build instructions (using zephyr-build MCP)
- Board-specific setup notes (nRF7002-DK vs ESP32)
- How to use with the Python tools
- Throughput server protocol description
- Troubleshooting section

**Pattern to follow:** Read `zephyr-apps/lib/crash_log/CLAUDE.md` for library documentation style.

**Acceptance criteria:**
- [ ] Both files exist and are non-empty
- [ ] `CLAUDE.md` covers API, Kconfig, BLE service, state machine, and testing
- [ ] `README.md` covers build, flash, usage with Python tools, and troubleshooting
- [ ] No placeholder text — all sections have real content

---

## Progress Tracking

The Ralph Loop should update `tasks/progress.txt` after each iteration with:
- Which user story was worked on
- What was accomplished
- Files created/modified
- Any gotchas or learnings for future iterations
- What to work on next

## Non-Goals

- No iOS/Android app (macOS Python tools only)
- No mDNS/DNS-SD discovery (use IP from BLE status query)
- No OTA firmware update
- No encryption on the BLE provisioning channel (Zephyr BLE pairing is out of scope)
- No web UI
- No cloud connectivity
