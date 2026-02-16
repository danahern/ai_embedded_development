# WiFi Provisioning App

Status: In-Progress (15/15 user stories pass, pending hardware verification)
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

- [ ] `wifi_prov` library builds for nrf7002dk, esp32_devkitc, and qemu_cortex_m3
- [ ] Unit tests pass on qemu_cortex_m3
- [ ] App flashes and boots on nRF7002-DK (validate_boot with "Booting Zephyr")
- [ ] App flashes and boots on ESP32-Eye
- [ ] macOS tool discovers device over BLE and connects
- [ ] WiFi scan returns AP list on both boards
- [ ] Credential provisioning connects to WiFi on both boards
- [ ] IP address queryable over BLE
- [ ] Credentials persist across reboot
- [ ] Factory reset erases credentials, device returns to advertising
- [ ] Throughput test runs bidirectionally with per-second stats
