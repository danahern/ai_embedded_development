# ESP-IDF App Template

Status: Ideation
Created: 2026-02-16

## Problem

Creating a new ESP-IDF app requires copying from `wifi_provision/` and gutting it. There's no equivalent of `zephyr-build.create_app()` for ESP-IDF. The Zephyr scaffolding system has templates and composable addons — ESP-IDF has nothing.

This is a developer experience problem: the first 30 minutes of any new ESP-IDF project are boilerplate setup (CMakeLists.txt, sdkconfig.defaults, component wrappers, main.c skeleton).

## Approach

Extend the `zephyr-build` MCP (or create a new tool in `esp-idf-build`) to scaffold ESP-IDF projects.

### Template Content

A basic ESP-IDF template would generate:

```
firmware/esp-idf/<name>/
  CMakeLists.txt                 # project() with EXTRA_COMPONENT_DIRS
  sdkconfig.defaults             # Sensible defaults (FreeRTOS HZ, stack sizes)
  main/
    CMakeLists.txt               # REQUIRES eai_osal + eai_log
    main.c                       # app_main() skeleton
    Kconfig.projbuild            # App-specific config options
```

### Composable Addons (like Zephyr)

| Addon | Adds |
|-------|------|
| `ble` | NimBLE component, GATT service skeleton, advertising |
| `wifi` | esp_wifi init, event handler, connect/disconnect |
| `nvs` | NVS init, eai_settings component |
| `tcp` | TCP server/client skeleton with OSAL thread |
| `test` | Unity test project skeleton alongside the app |

### Prerequisites

- Shared ESP-IDF components directory (see `plans/shared-espidf-components.md`)
- `eai_log` library (so templates use portable logging from day one)
- Either extend `esp-idf-build` MCP or add to `zephyr-build` as a multi-framework scaffolder

## Open Questions

- Extend `esp-idf-build` or create a unified `firmware-build` MCP?
- Should templates be YAML like Zephyr addons, or a different format?
- How to handle `sdkconfig.defaults` composition (e.g., BLE addon enables NimBLE)?
