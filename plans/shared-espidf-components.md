# Shared ESP-IDF Components Directory

Status: Ideation
Created: 2026-02-16

## Problem

Each ESP-IDF app (`wifi_provision`, `osal_tests`, `wifi_prov_tests`) has its own `components/` directory with duplicate CMakeLists.txt wrappers that point to `lib/` via relative paths. Adding a new app means copying these wrappers. Changing a component CMakeLists.txt means updating it in 3+ places.

Current duplication:
- `eai_osal/CMakeLists.txt` — identical in `wifi_provision/` and `osal_tests/`
- `wifi_prov_common/CMakeLists.txt` + shim headers — duplicated in `wifi_provision/` and `wifi_prov_tests/`

This gets worse with every new shared library (`eai_log`, `eai_settings`).

## Approach

Create a shared components directory at `firmware/esp-idf/components/` that all ESP-IDF apps reference via `EXTRA_COMPONENT_DIRS`.

### Target Structure

```
firmware/esp-idf/
  components/                    # Shared — one copy of each wrapper
    eai_osal/CMakeLists.txt
    eai_log/CMakeLists.txt
    eai_settings/CMakeLists.txt
    wifi_prov_common/
      CMakeLists.txt
      shim/zephyr/...
  wifi_provision/
    CMakeLists.txt               # EXTRA_COMPONENT_DIRS includes ../components + ./components
    components/                  # App-specific components only
      wifi_prov_esp/
      throughput_server/
  osal_tests/
    CMakeLists.txt               # EXTRA_COMPONENT_DIRS includes ../components
    main/
  wifi_prov_tests/
    CMakeLists.txt               # EXTRA_COMPONENT_DIRS includes ../components
    components/
      wifi_prov_cred/            # Test-specific (compiles just the cred file)
```

### Key Change

Each app's top-level CMakeLists.txt adds the shared directory:
```cmake
set(EXTRA_COMPONENT_DIRS
    "${CMAKE_CURRENT_SOURCE_DIR}/../components"     # Shared
    "${CMAKE_CURRENT_SOURCE_DIR}/components"         # App-specific
)
```

### Benefits

- One CMakeLists.txt per shared library component (not N copies)
- New apps get all shared libraries automatically
- Shim headers maintained in one place
- App-specific components (BLE, WiFi, throughput) stay in the app
