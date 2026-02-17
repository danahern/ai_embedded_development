# eai_ble — Portable BLE GATT Abstraction

Status: Complete
Created: 2026-02-16

## Problem

BLE GATT service implementation is the most expensive part of a multi-RTOS port. The wifi_prov BLE layer was fully rewritten:
- `wifi_prov_ble.c` (~280 lines) — Zephyr BT GATT (`bt_gatt_service_define`, `bt_le_adv_start`, `bt_gatt_notify`)
- `wifi_prov_ble_esp.c` (~350 lines) — NimBLE (`ble_gatts_add_svcs`, `ble_gap_adv_start`, `ble_gatts_notify_custom`)

Same UUIDs, same characteristic properties, same write/notify logic — different API calls. Every new BLE app (or BLE feature in an existing app) pays this cost again.

## Approach

Abstract at the GATT service level — not the full BLE stack, just the parts apps actually use. Consumer describes a service declaratively (UUIDs, properties, callbacks) and the backend handles platform-specific registration, advertising, and notification plumbing.

Key design decisions:
- **Char index, not handle.** Consumer references characteristics by 0-based index. Backend maps internally.
- **UUID in little-endian.** Matches BLE wire format. Both Zephyr and NimBLE store UUIDs in LE internally.
- **Write callback flattens data.** Backends extract raw bytes before calling consumer — no mbufs or bt_conn exposure.
- **Single service per registration.** Matches wifi_prov use case. Multiple services deferred.
- **Auto-restart advertising on disconnect.** Baked into both backends.

## Solution

6-function API with 3 backends:

```c
int  eai_ble_init(const struct eai_ble_callbacks *cbs);
int  eai_ble_gatt_register(const struct eai_ble_service *svc);
int  eai_ble_adv_start(const char *device_name);
int  eai_ble_adv_stop(void);
int  eai_ble_notify(uint8_t char_index, const uint8_t *data, uint16_t len);
bool eai_ble_is_connected(void);
```

Backends: Zephyr BT (dynamic GATT), NimBLE (ESP-IDF), POSIX stub (testing).

## Implementation Notes

### Files created
- `lib/eai_ble/include/eai_ble/eai_ble.h` — Public API, UUID macro, types
- `lib/eai_ble/src/zephyr/ble.c` — Zephyr backend (~250 lines)
- `lib/eai_ble/src/freertos/ble.c` — NimBLE backend (~280 lines)
- `lib/eai_ble/src/posix/ble.c` — POSIX stub (~100 lines)
- `lib/eai_ble/CMakeLists.txt`, `Kconfig`, `manifest.yml`, `zephyr/module.yml`
- `lib/eai_ble/tests/native/` — 9 Unity tests + vendored Unity
- `lib/eai_ble/tests/` — Zephyr build-only test (nrf52840dk)
- `lib/eai_ble/CLAUDE.md`

### Files modified
- `lib/CMakeLists.txt` — Added `add_subdirectory(eai_ble)`
- `lib/Kconfig` — Added `rsource "eai_ble/Kconfig"`

### Gotchas discovered
- **Zephyr 4.x CCC API change**: `_bt_gatt_ccc` deprecated → `bt_gatt_ccc_managed_user_data`. No `cfg_len` field. Use `BT_GATT_CCC_MANAGED_USER_DATA_INIT()`.
- **`CONFIG_BT_DEVICE_NAME_MAX` doesn't exist** in Zephyr 4.x. Used fixed 30-byte buffer.
- **UUID byte order**: Both Zephyr `bt_uuid_128.val[]` and NimBLE `ble_uuid128_t.value[]` store little-endian — direct memcpy from `eai_ble_uuid128_t`, no reversal needed.

## Modifications

- Dropped Linux/BlueZ backend (deferred to v2 as planned).
- NimBLE backend is code-only — no ESP-IDF test infrastructure yet.
- `eai_ble_init()` takes `const struct eai_ble_callbacks *cbs` parameter (not void) for connect/disconnect callbacks.

## Verification

1. **Native tests**: 9/9 pass ✓
2. **Zephyr build-only**: Compiles on nrf52840dk/nrf52840 ✓
3. **Existing tests**: Twister MCP has `zephyr_default` environment issue (pre-existing, not caused by eai_ble changes) — confirmed unrelated via direct build
