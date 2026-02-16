# WiFi Provisioning App

Status: Complete
Created: 2026-02-15

## Ralph Loop Experiment

This project is our first experiment with the Ralph Loop plugin (`/ralph-loop`). After this plan was approved, we generated a Ralph-format PRD (`tasks/prd-wifi-provision.md`) with phased user stories and clear completion criteria. That PRD is the Ralph Loop's input prompt.

**Workflow:** Plan → PRD → `/ralph-loop` with PRD → human hardware verification → capture learnings

## Problem

We need a cross-platform WiFi provisioning app that lets a macOS (or iOS/Android) device configure WiFi credentials on an embedded device over BLE. Once connected to WiFi, the device should support throughput testing. This needs to run on both nRF7002-DK and ESP32-Eye (original), sharing as much code as possible.

No existing app in the workspace does runtime WiFi provisioning — `ble_wifi_bridge` hardcodes credentials at compile time.

## Goals

1. **BLE advertising + connection** — Device advertises over BLE so a macOS app can discover and connect to it
2. **WiFi AP scanning** — Connected macOS app triggers the device to scan for nearby WiFi access points and returns results (SSID, RSSI, security type, channel)
3. **WiFi provisioning** — macOS app sends chosen SSID, password, and security type to the device over BLE; device connects to that WiFi network
4. **Credential persistence** — Device stores WiFi credentials so it auto-reconnects after reboot without re-provisioning
5. **IP address query** — macOS app can query the device's WiFi IP address over BLE once connected
6. **WiFi data transfer** — Once on WiFi, device can send and receive TCP data for throughput testing
7. **Bidirectional throughput testing** — macOS script connects to device over TCP and measures upload, download, and bidirectional throughput with per-second stats, jitter, and packet loss
8. **Factory reset** — BLE command causes the device to forget stored WiFi credentials and return to provisioning mode
9. **Cross-platform** — Same firmware codebase runs on both nRF7002-DK and ESP32-Eye (original), sharing maximum code via a shared library
10. **QEMU testability** — Business logic (credential store, protocol parsing, state machine) is unit-testable on qemu_cortex_m3 without hardware
11. **macOS test tools** — Python tools for both the BLE provisioning flow and the WiFi throughput testing

## Approach

### Architecture: Shared library + thin app + macOS tools

**1. `lib/wifi_prov/` — Shared WiFi provisioning library**

Reusable library following the same pattern as `crash_log` and `device_shell`. Provides:
- Custom BLE GATT service with structured characteristics (not NUS text)
- WiFi AP scanning via `net_mgmt`
- WiFi connection with runtime credentials
- Credential persistence via Zephyr Settings subsystem
- State machine: `idle → scanning → scan_complete → provisioning → connecting → connected`
- Auto-reconnect on boot if stored credentials exist
- Factory reset (erase credentials, disconnect)
- IP address query

GATT characteristics:
| Characteristic | Properties | Purpose |
|---------------|------------|---------|
| WiFi Scan Trigger | Write | Start AP scan |
| WiFi Scan Results | Notify | Stream discovered APs (SSID, RSSI, security, channel) |
| WiFi Credentials | Write | Receive SSID + password + security type |
| WiFi Status | Read, Notify | Connection state + IP address |
| Factory Reset | Write | Erase credentials, disconnect |

**2. `apps/wifi_provision/` — App**

Thin app that uses `wifi_prov` library and adds:
- TCP throughput server (bidirectional echo + stats)
- Throughput control via additional BLE characteristic
- Board configs for nRF7002-DK (`nrf7002dk/nrf5340/cpuapp`) and ESP32 (`esp32_devkitc/esp32/procpu`)

**3. `test-tools/` — macOS test tools (Python)**

- `wifi_provision_tool.py` — BLE client using `bleak`: discover, scan APs, provision, query IP, factory reset
- `throughput_test.py` — TCP client: upload/download/bidirectional tests with per-second stats, jitter, packet loss

**4. `lib/wifi_prov/tests/` — Unit tests on QEMU**

Test what doesn't need hardware: credential storage, protocol message serialization, state machine transitions. Use `qemu_cortex_m3`.

### Cross-platform strategy

Zephyr's BLE and WiFi APIs are platform-agnostic. The `wifi_prov` library uses:
- `bt_gatt_service_define()` — same on nRF and ESP32
- `net_mgmt(NET_REQUEST_WIFI_*)` — same API, different drivers underneath
- `settings_*()` — NVS backend on both platforms

Board-specific concerns:
- **nRF7002-DK**: nRF5340 + nRF7002 companion IC. May need WPA supplicant config. Flash with `.hex` via J-Link.
- **ESP32**: Built-in WiFi. May need ESP-specific WiFi Kconfig. Flash via esptool.
- **QEMU**: No WiFi/BLE. Unit tests only for credential store, message parsing, state machine.

### Key files to reuse/reference

- `apps/ble_wifi_bridge/src/wifi_manager.c` — WiFi connect/disconnect pattern, DHCP IP tracking
- `apps/ble_wifi_bridge/src/ble_nus.c` — BLE module pattern (not the NUS service itself)
- `apps/ble_wifi_bridge/prj.conf` — Working BLE + WiFi + networking Kconfig baseline
- `lib/crash_log/` — Shared library structure template (CMakeLists, Kconfig, conf/, boards/, tests/)
- `zephyr/samples/bluetooth/peripheral/src/main.c` — Custom GATT service pattern

### QEMU testing strategy

Can test on QEMU:
- Credential store (Settings with RAM backend)
- Protocol message encode/decode
- State machine transitions (mock WiFi/BLE events)

Cannot test on QEMU:
- Actual BLE advertising/connection
- Actual WiFi scanning/connection
- Throughput

Use `testcase.yaml` with `integration_platforms: [qemu_cortex_m3]` for unit tests, and `platform_allow` with `build_only: true` for build verification on real boards.

## Deliverables

**Phase 0 (before Ralph):**
1. This plan at `plans/wifi-provision.md`
2. Ralph-format PRD at `tasks/prd-wifi-provision.md`

**Built by Ralph Loop:**
3. `lib/wifi_prov/` — shared library with Kconfig, CMakeLists, GATT service, wifi manager, credential store
4. `lib/wifi_prov/tests/` — unit tests on QEMU
5. `apps/wifi_provision/` — app with throughput server, board configs
6. `test-tools/wifi_provision_tool.py` — macOS BLE provisioning client
7. `test-tools/throughput_test.py` — macOS TCP throughput tester
8. Board overlays/configs for nrf7002dk and esp32_devkitc

**Post-Ralph (human verification):**
9. Flash and test on real nRF7002-DK and ESP32-Eye hardware
10. Capture learnings from the Ralph Loop experiment via `/learn`

## Verification

- [x] `wifi_prov` library builds for nrf7002dk, esp32_devkitc, and qemu_cortex_m3
- [x] Unit tests pass on qemu_cortex_m3 (22/22 tests pass)
- [x] App flashes and boots on nRF7002-DK (validate_boot with "Booting Zephyr")
- [x] App builds for ESP32-DevKitC (no hardware to flash-test)
- [x] macOS tool discovers device over BLE and connects
- [x] WiFi scan returns AP list on nRF7002-DK (found dan_and_mich on ch1/ch40)
- [x] Credential provisioning connects to WiFi on nRF7002-DK (192.168.1.59)
- [x] IP address queryable over BLE (192.168.1.59 returned via status notification)
- [x] Credentials persist across reboot (auto-connect fires at t+2s, WiFi connected at t+7s)
- [x] Factory reset erases credentials, device returns to advertising
- [x] Throughput test runs bidirectionally with per-second stats (upload: 336 Kbps, download: 393 Kbps, echo: 150 Kbps)

### Hardware verification notes (2026-02-15)

**Bugs found and fixed during hardware verification:**
1. BLE GATT write callback blocked BLE thread — deferred to k_work (wifi_prov.c)
2. BLE prepare write support needed for payloads > ATT MTU — added BT_GATT_PERM_PREPARE_WRITE + BT_GATT_WRITE_FLAG_PREPARE handling
3. MTU config needed — added CONFIG_BT_L2CAP_TX_MTU=100, CONFIG_BT_BUF_ACL_RX_SIZE=104
4. settings_subsys_init() missing — credentials failed to persist to NVS
5. WiFi connect race condition — k_sem_take fired on transient WPA supplicant failure; switched to async connect
6. bleak BLEDevice.rssi removed — fixed to use return_adv=True
7. CoreBluetooth UUID expiration — added find_device() helper for fresh scan before connect
8. RTT buffer too small — increased SEGGER_RTT_BUFFER_SIZE_UP to 4096
9. Settings cred_set returned positive byte count instead of 0 — `read_cb()` returns bytes read, but Settings expects 0 on success
10. Auto-connect at boot failed (-134) — WiFi driver not ready; deferred with `k_work_delayable` + 2s delay
11. Factory reset crashed (stack overflow) — `wpa_cli_cmd_disconnect` overflowed 4096-byte system workqueue; increased to 8192
12. Factory reset in BLE callback caused disconnect before response — deferred to `k_work_submit()`
13. Throughput server stack overflow — STACK_SIZE=4096 with 4096-byte buffer on stack; increased stack to 8192, reduced buffer to 1024
14. Python socket timeout persisted after connect — `socket.create_connection(timeout=5)` leaves timeout on socket; added `settimeout(None)`

**nRF7002-DK setup requirements:**
- Network core needs hci_ipc firmware for BLE (HCI error -11 without it)
- APPROTECT must be cleared: `nrfutil device recover`
- Flash via nrfutil: `nrfutil device program --firmware <hex> --core Application --traits jlink`
- probe-rs connection disrupts BLE advertising — disconnect before BLE operations

## Solution

WiFi provisioning over BLE with TCP throughput testing, working end-to-end on nRF7002-DK.

**Library (`lib/wifi_prov/`):**
- Custom BLE GATT service with 5 characteristics (scan trigger, scan results, credentials, status, factory reset)
- WiFi management via `net_mgmt()` API — scan, connect, disconnect
- Credential persistence via Zephyr Settings subsystem (NVS backend)
- State machine: idle → scanning → scan_complete → provisioning → connecting → connected
- Auto-connect on boot with 2-second delay for WiFi driver initialization
- Factory reset deferred to k_work to avoid BLE callback stack overflow
- 22 unit tests covering credentials, message encoding, and state machine

**App (`apps/wifi_provision/`):**
- TCP throughput server on port 4242 (echo, sink, source modes)
- Board configs for nRF7002-DK and ESP32-DevKitC

**Test tools:**
- `wifi_provision_tool.py` — BLE client: discover, scan-aps, provision, status, factory-reset
- `throughput_test.py` — TCP client: upload/download/echo with per-second stats and jitter

**Throughput results (nRF7002-DK, WiFi):**
| Mode | Avg | Min | Max | Jitter |
|------|-----|-----|-----|--------|
| Upload | 336 Kbps | 46 Kbps | 1.28 Mbps | 133% |
| Download | 393 Kbps | 109 Kbps | 554 Kbps | 40% |
| Echo | 150 Kbps | 76 Kbps | 221 Kbps | 36% |

## Implementation Notes

- 14 bugs found and fixed during hardware verification (see list above)
- Key pattern: **all heavy operations must be deferred from BLE GATT callbacks** via `k_work`. BLE RX thread has limited stack and blocking it causes connection timeouts.
- WPA supplicant sends transient CONNECT_RESULT with status=1 before the real connection succeeds. Must not treat as final failure.
- `CONFIG_SYSTEM_WORKQUEUE_STACK_SIZE=8192` needed for WPA supplicant disconnect operations.
- BLE re-advertising fails with ENOMEM (-12) after provisioning disconnect — non-critical, logged as warning.
- ESP32 build succeeds but RTT logging config warnings expected (ESP32 doesn't have Segger RTT; needs UART backend).
- Twister on macOS requires removing pyenv shims from PATH to avoid noise in cmake's toolchain detection output.

## Modifications

- Dropped ESP32 flash verification (no ESP32-DevKitC connected during testing). Build-verified only.
- Echo throughput test required socket timeout increase (2s → 5s) and smaller block size (4096 → 512) due to WiFi link latency.
- Ralph Loop experiment was successful for scaffolding (15/15 user stories implemented), but hardware verification found 14 additional bugs that required manual debugging.
