# eai_log — Portable Logging Abstraction

Status: Ideation
Created: 2026-02-16

## Problem

Every shared library in `lib/` that uses logging is coupled to Zephyr's `LOG_MODULE_REGISTER` / `LOG_INF` / `LOG_ERR` macros. When we ported wifi_prov to ESP-IDF, we worked around this with shim headers (`shim/zephyr/logging/log.h` mapping `LOG_INF` → `ESP_LOGI`). This approach has three problems:

1. **Doesn't scale.** Each ESP-IDF app duplicates the shim. Each new platform (Linux, bare-metal) needs its own shim.
2. **Fragile.** The shim only covers macros we've used so far. New Zephyr logging features (`LOG_HEXDUMP_INF`, `LOG_DATA`, etc.) break silently.
3. **Wrong dependency direction.** Shared libraries should depend on a portable logging API, not on Zephyr with a compatibility layer.

This is the prerequisite for all future shared libraries — `eai_log` must exist before `eai_settings`, `eai_ble`, or `eai_wifi`.

## Approach

Lightweight header-only (or header + thin .c) logging library that compiles to the native logging system on each platform.

### API Surface

```c
#include <eai_log/eai_log.h>

EAI_LOG_MODULE_REGISTER(wifi_prov, EAI_LOG_LEVEL_INF);

EAI_LOG_INF("Connected to %s (RSSI %d)", ssid, rssi);
EAI_LOG_ERR("Failed to connect: %d", err);
EAI_LOG_WRN("Retry in %d ms", delay);
EAI_LOG_DBG("State transition: %d -> %d", old, new);
```

### Backend Mapping

| Platform | EAI_LOG_INF(...) compiles to |
|----------|------------------------------|
| Zephyr | `LOG_INF(...)` via `<zephyr/logging/log.h>` |
| ESP-IDF | `ESP_LOGI(TAG, ...)` via `esp_log.h` |
| Linux | `fprintf(stderr, "[INF] %s: " fmt, TAG, ...)` |
| Bare-metal | `printf(...)` or NOP (configurable) |

### Design Decisions

- **Header-only preferred.** Macros expand to the native call directly — zero overhead, no function call indirection.
- **Module registration creates TAG.** `EAI_LOG_MODULE_REGISTER(name, level)` expands to whatever the backend needs (`LOG_MODULE_REGISTER` on Zephyr, `static const char *TAG = "name"` on ESP-IDF/Linux).
- **Level filtering at compile time.** `EAI_LOG_LEVEL_INF` maps to the backend's level system. On platforms without compile-time filtering, use `#if` guards.
- **No runtime configuration in v1.** Keep it simple — compile-time level selection only. Runtime log level changes can come later.

### Directory Structure

```
lib/eai_log/
  include/eai_log/
    eai_log.h           # Public API (includes backend via conditional)
  src/
    zephyr/eai_log_impl.h
    freertos/eai_log_impl.h    # ESP-IDF uses this
    linux/eai_log_impl.h
  Kconfig               # CONFIG_EAI_LOG (Zephyr integration)
  CMakeLists.txt
```

### Migration Path

1. Create `eai_log` library
2. Migrate `lib/wifi_prov/` to use `EAI_LOG_*` instead of Zephyr `LOG_*`
3. Remove shim headers from ESP-IDF components
4. Migrate other shared libs (`crash_log`, `device_shell`, `eai_osal`)
5. All new shared libs use `eai_log` from day one
