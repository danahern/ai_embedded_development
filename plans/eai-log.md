# eai_log — Portable Logging Abstraction

Status: Complete
Created: 2026-02-16

## Problem

Every shared library in `lib/` that uses logging is coupled to Zephyr's `LOG_MODULE_REGISTER` / `LOG_INF` / `LOG_ERR` macros. When we ported wifi_prov to ESP-IDF, we worked around this with shim headers (`shim/zephyr/logging/log.h` mapping `LOG_INF` → `ESP_LOGI`). This approach has three problems:

1. **Doesn't scale.** Each ESP-IDF app duplicates the shim. Each new platform (Linux, bare-metal) needs its own shim.
2. **Fragile.** The shim only covers macros we've used so far. New Zephyr logging features (`LOG_HEXDUMP_INF`, `LOG_DATA`, etc.) break silently.
3. **Wrong dependency direction.** Shared libraries should depend on a portable logging API, not on Zephyr with a compatibility layer.

This is the prerequisite for all future shared libraries — `eai_log` must exist before `eai_settings`, `eai_ble`, or `eai_wifi`.

## Approach

Header-only logging library that compiles to the native logging system on each platform. Zero overhead — macros expand directly to platform calls. Backend selected at compile time via Kconfig (Zephyr) or compile definitions (ESP-IDF, POSIX).

## Solution

Created `lib/eai_log/` with:

- **Public API** (`include/eai_log/eai_log.h`) — Log level defines + backend dispatch via conditional `#include`
- **Zephyr backend** (`src/zephyr.h`) — Direct passthrough to `LOG_MODULE_REGISTER`, `LOG_INF/ERR/WRN/DBG`
- **FreeRTOS backend** (`src/freertos.h`) — Static TAG variable + `ESP_LOGI/E/W/D`
- **POSIX backend** (`src/posix.h`) — `fprintf(stderr)` with per-module compile-time level filtering
- **Kconfig** — `CONFIG_EAI_LOG` with `CONFIG_EAI_LOG_BACKEND_ZEPHYR` choice (depends on LOG)
- **5 native tests** — All passing (compile_all_levels, module_register, level_filtering, format_args, module_declare)

## Implementation Notes

- Backend headers are in `src/` not `src/<platform>/` since they're single files, not directories
- POSIX backend uses `##__VA_ARGS__` GNU extension for zero-arg format strings — GCC/Clang only, acceptable for desktop backend
- `EAI_LOG_MODULE_REGISTER` must be at file scope (Zephyr creates a static struct)
- Never use both REGISTER and DECLARE in the same file — ESP-IDF/POSIX create duplicate variables

## Modifications

- Dropped bare-metal backend from initial scope — can be added when needed
- No runtime level configuration — compile-time only, keeps it simple
- Directory structure simplified: `src/zephyr.h` instead of `src/zephyr/eai_log_impl.h`
