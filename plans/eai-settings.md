# eai_settings — Portable Key-Value Store

Status: Ideation
Created: 2026-02-16

## Problem

WiFi credential persistence required two separate implementations:
- `wifi_prov_cred.c` — Zephyr Settings subsystem (`settings_save_one`, `settings_load_subtree`)
- `wifi_prov_cred_esp.c` — ESP-IDF NVS (`nvs_set_blob`, `nvs_get_blob`)

Both implement the same API (`wifi_prov_cred_store/load/erase/exists`) with different backends. This is exactly the OSAL pattern — same interface, platform-specific implementation — but there's no abstraction layer.

Every future feature that needs persistent storage (device config, calibration data, user preferences, OTA state) will face the same problem: write it twice, test it twice, maintain it twice.

## Approach

Compile-time key-value store abstraction following the OSAL design pattern.

### API Surface

```c
#include <eai_settings/eai_settings.h>

int eai_settings_init(void);

int eai_settings_set(const char *key, const void *data, size_t len);
int eai_settings_get(const char *key, void *data, size_t max_len, size_t *actual_len);
int eai_settings_delete(const char *key);
bool eai_settings_exists(const char *key);

int eai_settings_set_u8(const char *key, uint8_t value);
int eai_settings_get_u8(const char *key, uint8_t *value);
/* set_u16, set_u32, set_str convenience wrappers */
```

### Backend Mapping

| Platform | Backend | Init |
|----------|---------|------|
| Zephyr | Settings subsystem (`settings_save_one`, etc.) | `settings_subsys_init()` |
| ESP-IDF | NVS (`nvs_set_blob`, etc.) | `nvs_flash_init()` |
| Linux | File-based (JSON or SQLite) | `mkdir -p ~/.eai/settings/` |

### Return Values (API Contract)

| Return | Meaning |
|--------|---------|
| `0` | Success |
| `-EINVAL` | Invalid parameters (null key, null data, zero length) |
| `-ENOENT` | Key not found |
| `-ENOSPC` | Storage full |
| `-EIO` | Backend I/O error |

### Design Decisions

- **Flat key namespace.** No hierarchical paths (Zephyr Settings uses `/wifi/ssid`, NVS uses namespace+key). Flatten to simple string keys. Backend maps as needed.
- **Blob-first API.** Primary interface is `set(key, data, len)` / `get(key, data, max_len)`. Typed convenience wrappers (`set_u8`, `set_str`) call the blob API.
- **Namespace isolation.** Each library gets its own namespace/prefix. `eai_settings_init()` takes an optional namespace parameter, or libraries prefix their keys.
- **Same OSAL dispatch pattern.** `include/eai_settings/types.h` includes backend-specific types via relative path.

### Migration

1. Create `eai_settings` library with Zephyr + ESP-IDF + Linux backends
2. Rewrite `wifi_prov_cred.c` to use `eai_settings_set/get/delete`
3. Remove `wifi_prov_cred_esp.c` — one credential implementation for all platforms
4. Port credential tests to use `eai_settings` — same tests run on QEMU, ESP32, and native
