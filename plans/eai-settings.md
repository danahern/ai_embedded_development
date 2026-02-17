# eai_settings — Portable Key-Value Store

Status: Complete
Created: 2026-02-16

## Problem

WiFi credential persistence required two separate implementations:
- `wifi_prov_cred.c` — Zephyr Settings subsystem (`settings_save_one`, `settings_load_subtree`)
- `wifi_prov_cred_esp.c` — ESP-IDF NVS (`nvs_set_blob`, `nvs_get_blob`)

Both implement the same API (`wifi_prov_cred_store/load/erase/exists`) with different backends. This is exactly the OSAL pattern — same interface, platform-specific implementation — but there's no abstraction layer.

Every future feature that needs persistent storage (device config, calibration data, user preferences, OTA state) will face the same problem: write it twice, test it twice, maintain it twice.

## Approach

Compile-time key-value store abstraction following the OSAL design pattern. Blob-first API with `"namespace/key"` format. Three backends: Zephyr Settings, ESP-IDF NVS, and POSIX file-based.

## Solution

Created `lib/eai_settings/` with:

- **Public API** (`include/eai_settings/eai_settings.h`) — 5 functions: `init`, `set`, `get`, `delete`, `exists`
- **Zephyr backend** (`src/zephyr/settings.c`) — Uses `SETTINGS_STATIC_HANDLER_DEFINE` at "eai" prefix, `settings_save_one`/`settings_load_subtree`, K_MUTEX for thread safety
- **FreeRTOS backend** (`src/freertos/settings.c`) — NVS with namespace/key parsing (15 char limit), `nvs_flash_init` with erase-on-corrupt recovery
- **POSIX backend** (`src/posix/settings.c`) — File-based at `<base_path>/<namespace>/<key>`, pthread_mutex for thread safety
- **14 native tests** — All passing with sanitizers clean
- **14 Zephyr tests** — All passing on mps2/an385

## Implementation Notes

- **qemu_cortex_m3 has no flash driver** — lm3s6965 stellaris chip has no flash driver in Zephyr, making NVS impossible. Must use `mps2/an385` for Settings/NVS tests.
- NVS sector size on mps2/an385 is 1KB — large value test uses 256 bytes (not 1024) to fit within sector constraints.
- Zephyr backend uses a static `load_ctx` struct for `settings_load_subtree` callback — protected by K_MUTEX.
- POSIX backend base path is compile-time via `EAI_SETTINGS_BASE_PATH` define (default `/tmp/eai_settings`).
- FreeRTOS backend enforces 15-char limit on both namespace and key via `parse_key` helper.

## Modifications

- Dropped typed convenience wrappers (`set_u8`, `set_str`) from initial scope — blob API is sufficient
- Dropped `-ENOSPC` return code — not needed for current backends
- Large value Zephyr test reduced to 256 bytes (was 1024) due to NVS sector size constraints
- Test platform changed from `qemu_cortex_m3` to `mps2/an385` — QEMU lm3s6965 lacks flash driver entirely
