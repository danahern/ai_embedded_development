# eai_ble — Portable BLE GATT Abstraction

Status: Ideation
Created: 2026-02-16

## Problem

BLE GATT service implementation is the most expensive part of a multi-RTOS port. The wifi_prov BLE layer was fully rewritten:
- `wifi_prov_ble.c` (~280 lines) — Zephyr BT GATT (`bt_gatt_service_define`, `bt_le_adv_start`, `bt_gatt_notify`)
- `wifi_prov_ble_esp.c` (~350 lines) — NimBLE (`ble_gatts_add_svcs`, `ble_gap_adv_start`, `ble_gatts_notify_custom`)

Same UUIDs, same characteristic properties, same write/notify logic — different API calls. Every new BLE app (or BLE feature in an existing app) pays this cost again.

## Approach

Abstract at the GATT service level — not the full BLE stack, just the parts apps actually use.

### Candidate API Surface

```c
#include <eai_ble/eai_ble.h>

/* Init / advertising */
int eai_ble_init(void);
int eai_ble_adv_start(const char *device_name, const uint8_t *svc_uuid128);
int eai_ble_adv_stop(void);

/* GATT service registration */
typedef void (*eai_ble_write_cb_t)(uint16_t char_handle, const uint8_t *data, uint16_t len);
typedef void (*eai_ble_read_cb_t)(uint16_t char_handle, uint8_t *buf, uint16_t *len);

struct eai_ble_char {
    const uint8_t *uuid128;
    uint8_t properties;          /* EAI_BLE_PROP_READ | WRITE | NOTIFY */
    eai_ble_write_cb_t on_write;
    eai_ble_read_cb_t on_read;
};

struct eai_ble_service {
    const uint8_t *uuid128;
    const struct eai_ble_char *chars;
    uint16_t char_count;
};

int eai_ble_gatt_register(const struct eai_ble_service *svc);
int eai_ble_gatt_notify(uint16_t char_handle, const uint8_t *data, uint16_t len);
```

### Backend Mapping

| OSAL | Zephyr BT | NimBLE (ESP-IDF) | Linux (BlueZ) |
|------|-----------|------------------|---------------|
| `eai_ble_init()` | `bt_enable()` | `nimble_port_init()` | `hci_open_dev()` |
| `eai_ble_adv_start()` | `bt_le_adv_start()` | `ble_gap_adv_start()` | `hci_le_set_advertise_enable()` |
| `eai_ble_gatt_register()` | `bt_gatt_service_register()` | `ble_gatts_add_svcs()` | D-Bus GATT API |
| `eai_ble_gatt_notify()` | `bt_gatt_notify()` | `ble_gatts_notify_custom()` | D-Bus notify |

### Challenges

- **Service definition macros.** Zephyr uses `BT_GATT_SERVICE_DEFINE` (static, compile-time). NimBLE uses runtime registration. Abstraction must work for both.
- **Connection handles.** Zephyr passes `bt_conn*`, NimBLE uses `uint16_t conn_handle`. Need an opaque connection type.
- **MTU negotiation.** Notification size depends on negotiated MTU. Different APIs to query it.
- **Security/pairing.** Out of scope for v1 — focus on unencrypted GATT first.

### Scope (v1)

- Single BLE peripheral role (no central/scanner)
- One GATT service with up to 8 characteristics
- Read, Write, Notify properties
- No pairing/bonding
- Backends: Zephyr BT, NimBLE (ESP-IDF)
- Linux (BlueZ) deferred to v2
