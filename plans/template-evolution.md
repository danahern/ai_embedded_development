# Template Evolution: Composable App Addons

Status: Complete
Created: 2026-02-14

## Problem

The workspace has three distinct embedded patterns — BLE, WiFi, TCP — that were hardcoded in individual apps. Creating a new app with BLE required manually copying ~80 lines of boilerplate from `ble_data_transfer`. The `create_app` MCP tool only had a single "core" template with logging and crash debug.

## Approach

Addons are YAML files in `zephyr-apps/addons/<name>.yml` — no MCP rebuild needed to add new ones. Each addon contributes Kconfig entries, `#include` lines, global declarations, and `main()` init code. The existing `libraries` parameter in `create_app` resolves names against both `lib/<name>/manifest.yml` (libraries → overlay injection) and `addons/<name>.yml` (addons → code generation).

## Solution

Composable addons that layer BLE, WiFi, and/or TCP boilerplate onto the core template. Users specify `create_app(name="my_app", libraries=["ble", "wifi"])` and get a compilable app with full advertising, connection callbacks, WiFi management, etc.

### Addon YAML schema

Each addon file has five optional code sections: `kconfig`, `includes`, `globals`, `init`. The `kconfig` section supports `{{APP_NAME}}` substitution.

### Resolution flow

For each name in `libraries=["crash_log", "ble", "wifi"]`:
1. Check `lib/<name>/manifest.yml` → **library** (overlay injection, existing behavior)
2. If not found, check `addons/<name>.yml` → **addon** (code generation)
3. If neither found, error with message listing both paths checked

### Available addons

- `ble.yml` — BLE peripheral with NUS: advertising, connection callbacks, NUS echo
- `wifi.yml` — WiFi station: net_mgmt events, connect/disconnect handlers, DHCP
- `tcp.yml` — TCP client: socket connect/send/recv, dedicated RX thread

## Implementation Notes

### Files modified (MCP — requires rebuild)

| File | Changes |
|------|---------|
| `claude-mcps/zephyr-build/src/tools/types.rs` | Added `AddonManifest`, `AddonInfo` structs; added `addons` field to `ListTemplatesResult` |
| `claude-mcps/zephyr-build/src/tools/templates.rs` | Added `{{ADDON_KCONFIG}}`, `{{ADDON_INCLUDES}}`, `{{ADDON_GLOBALS}}`, `{{ERR_DECL}}`, `{{ADDON_INIT}}` placeholders; added `merge_addon_code()` function; 8 new tests |
| `claude-mcps/zephyr-build/src/tools/build_tools.rs` | Added `get_addons_dir()`, `read_addon_manifest()`, `list_available_addons()`; modified `create_app()` for addon resolution; modified `list_templates()` to return addons; 6 new tests |

### Files created (workspace — no rebuild)

| File | Content |
|------|---------|
| `zephyr-apps/addons/ble.yml` | BLE peripheral with NUS |
| `zephyr-apps/addons/wifi.yml` | WiFi station with DHCP |
| `zephyr-apps/addons/tcp.yml` | TCP client socket |

### Files updated (docs)

| File | Changes |
|------|---------|
| `claude-mcps/zephyr-build/CLAUDE.md` | Documented addon support in `create_app`, `list_templates` |
| `zephyr-apps/CLAUDE.md` | Documented `addons/` directory and available addons |

### Key design decisions

- `{{ERR_DECL}}` only emitted when addons have init code — avoids unused variable warnings
- Addons are sorted alphabetically in `list_templates` output for deterministic ordering
- YAML-based addons require no MCP rebuild to add new ones
- `merge_addon_code()` handles concatenation with proper separators and indentation

## Modifications

- Original plan was for pattern detection and template suggestion. Pivoted to composable addons as a more practical approach.
- `tcp.yml` init is intentionally minimal (just a log message) since TCP connect must be deferred until WiFi is ready.
