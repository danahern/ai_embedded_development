⏺ Retrospective: Adding FreeRTOS/ESP-IDF to a Zephyr Codebase

  What We Started With

  A Zephyr-only stack:
  - zephyr-apps/ submodule with 4 apps, 4 shared libraries
  - OSAL with Zephyr-only backend (9 primitives, 44 tests)
  - WiFi provisioning library tightly coupled to Zephyr APIs (BT GATT, net_mgmt, Settings subsystem)
  - All tests on qemu_cortex_m3 via twister
  - MCP tooling built around west and probe-rs

  What We Delivered

  Same WiFi provisioning app running on ESP32 with identical BLE protocol — macOS Python tools can't tell the difference between the nRF7002-DK and ESP32.

  By the numbers:
  - ~15K lines of new code (app + OSAL backend + tests)
  - 88 tests passing across both platforms (44 OSAL + 22 wifi_prov on ESP32, 22 wifi_prov on QEMU)
  - 6/6 hardware integration tests on ESP32 DevKitC
  - 10 knowledge items captured
  - 1 submodule renamed (zephyr-apps → firmware)

  ---
  What Went Well

  1. The OSAL design paid off immediately

  The OSAL's compile-time backend dispatch (#include "../../src/freertos/types.h") meant zero runtime overhead and zero API changes for consuming code. The
  orchestrator (wifi_prov.c) uses eai_osal_work_submit() — it doesn't know or care whether that's k_work_submit() or a FreeRTOS task+queue underneath.

  The work queue abstraction was the hardest primitive (FreeRTOS has no native equivalent), but once built, it unlocked the entire orchestration layer.

  2. Portability analysis up front saved massive time

  Before writing code, we analyzed every source file in lib/wifi_prov/src/ and categorized each as portable, portable via OSAL, or platform-specific. This produced a
   clean split:

  ┌───────────────────┬─────────────────────────────────────────────────────┬────────────────────────────────────────┐
  │     Category      │                        Files                        │                Strategy                │
  ├───────────────────┼─────────────────────────────────────────────────────┼────────────────────────────────────────┤
  │ Portable as-is    │ wifi_prov_sm.c, wifi_prov_msg.c                     │ Compile unchanged with shim headers    │
  ├───────────────────┼─────────────────────────────────────────────────────┼────────────────────────────────────────┤
  │ Portable via OSAL │ wifi_prov.c, throughput_server.c                    │ Replace k_work → OSAL, zsock_* → POSIX │
  ├───────────────────┼─────────────────────────────────────────────────────┼────────────────────────────────────────┤
  │ Platform-specific │ wifi_prov_ble.c, wifi_prov_wifi.c, wifi_prov_cred.c │ Rewrite for NimBLE, esp_wifi, NVS      │
  └───────────────────┴─────────────────────────────────────────────────────┴────────────────────────────────────────┘

  No surprises during implementation because we knew exactly what needed rewriting.

  3. Same wire protocol = same test tools

  Keeping identical GATT UUIDs and binary wire formats meant hw-test-runner (BLE discover, provision, throughput, factory reset) works against both boards with zero
  changes. This is the single biggest win for scale — one test harness, N platforms.

  4. Standalone test projects are the right pattern

  Separate ESP-IDF projects for tests (osal_tests/, wifi_prov_tests/) rather than embedded test directories. They build independently, have their own
  sdkconfig.defaults, and don't pollute the app build. Easy to flash and run — just idf.py flash monitor.

  5. Knowledge capture during implementation

  Capturing gotchas as they happened (WiFi power management, StackType_t sizes, CoreBluetooth GATT cache) means the next person hitting these issues gets them
  injected automatically via .claude/rules/ files.

  ---
  What Could Be Done Better

  1. The Zephyr shim is a hack, not an architecture

  Currently, wifi_prov_common/shim/zephyr/logging/log.h maps LOG_INF → ESP_LOGI. This works for 2 files. It won't scale to 20 files or 5 platforms. We need:

  - A real logging abstraction in the OSAL (or a separate eai_log library)
  - eai_log_info(TAG, fmt, ...) that maps to LOG_INF / ESP_LOGI / printf at compile time
  - Every shared library should use this, not Zephyr's LOG_MODULE_REGISTER

  2. No shared credential abstraction

  wifi_prov_cred.c (Zephyr Settings) and wifi_prov_cred_esp.c (NVS) implement the same API with different backends — exactly like the OSAL pattern. But there's no
  abstraction layer. If we add a third platform, we write a third credential file. This should be:

  - eai_kv or eai_settings — key-value store abstraction in the OSAL
  - Backends: Zephyr Settings, NVS, littlefs, SQLite (Linux)
  - Same compile-time dispatch pattern as OSAL primitives

  3. BLE and WiFi HALs don't exist

  The BLE GATT service was fully rewritten for NimBLE (~280 lines Zephyr, ~350 lines ESP-IDF). Same UUIDs, same logic, different API calls. The WiFi driver was
  similarly rewritten. These are the most expensive parts to port, and there's no abstraction path today.

  Possible approaches:
  - BLE: Abstract at the GATT service level — eai_ble_gatt_register_service(), eai_ble_gatt_notify(). Hide bt_gatt_* vs ble_gatts_* behind a compile-time backend.
  - WiFi: Abstract at the connection manager level — eai_wifi_scan(), eai_wifi_connect(), eai_wifi_get_ip(). The scan results delivery difference (per-result vs
  batch) is the hardest part.

  4. Build system integration is fragile

  ESP-IDF components reference shared libs via relative paths (../../../../lib/eai_osal). This works but:
  - Breaks if directory structure changes
  - No equivalent of Zephyr's module.yml for automatic discovery
  - Each new ESP-IDF app duplicates the component wrappers

  We need a better pattern — maybe a shared components/ directory at the firmware/esp-idf/ level that all apps include.

  5. ESP-IDF MCP tooling isn't production-ready

  The esp-idf-build MCP failed because it doesn't inherit the ESP-IDF shell environment (IDF_PATH, toolchain paths). We fell back to raw idf.py commands with
  explicit PATH and IDF_PATH every time. This needs fixing — either the MCP server sources the ESP-IDF environment, or it accepts env vars in its config.

  6. No CI for ESP-IDF tests

  Zephyr tests run on QEMU in CI. ESP-IDF Unity tests require real hardware (or QEMU for ESP32 which is experimental). We have no automated pipeline for the 66
  ESP-IDF tests. Options:
  - ESP32 QEMU (community-maintained, limited)
  - Self-hosted runner with real ESP32 (we have danahern-pc — could add a DevKitC)
  - Run on flash before merge (manual gate)

  ---
  What We Should Share / Extract as Libraries

  Based on what we learned, here's the priority order for new shared abstractions:

  Tier 1: High Impact, Clear Pattern

  ┌───────────────────────────────┬───────────────────────────────────────────────────────────────────────────────┬────────────────────────┐
  │            Library            │                                      Why                                      │         Effort         │
  ├───────────────────────────────┼───────────────────────────────────────────────────────────────────────────────┼────────────────────────┤
  │ eai_log                       │ Every shared file needs logging. Shim headers don't scale.                    │ Small — macro wrappers │
  ├───────────────────────────────┼───────────────────────────────────────────────────────────────────────────────┼────────────────────────┤
  │ eai_kv                        │ Credential store, config storage, any persistent data. NVS/Settings/littlefs. │ Medium — 3 backends    │
  ├───────────────────────────────┼───────────────────────────────────────────────────────────────────────────────┼────────────────────────┤
  │ Shared ESP-IDF components dir │ Stop duplicating eai_osal/ and wifi_prov_common/ CMakeLists.txt per app       │ Small — restructure    │
  └───────────────────────────────┴───────────────────────────────────────────────────────────────────────────────┴────────────────────────┘

  Tier 2: High Impact, Harder

  ┌──────────┬─────────────────────────────────────────────────────────────────────────────────┬─────────────────────────────────────────┐
  │ Library  │                                       Why                                       │                 Effort                  │
  ├──────────┼─────────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────┤
  │ eai_ble  │ BLE GATT is the most expensive rewrite. Abstract service registration + notify. │ Large — BLE stacks differ significantly │
  ├──────────┼─────────────────────────────────────────────────────────────────────────────────┼─────────────────────────────────────────┤
  │ eai_wifi │ WiFi scan/connect is the second most expensive. Abstract connection manager.    │ Large — event models differ             │
  └──────────┴─────────────────────────────────────────────────────────────────────────────────┴─────────────────────────────────────────┘

  Tier 3: Nice to Have

  ┌────────────────────┬─────────────────────────────────────────────────────────────────────────────────────┬────────────────────────────────────┐
  │      Library       │                                         Why                                         │               Effort               │
  ├────────────────────┼─────────────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────┤
  │ eai_net            │ TCP/UDP socket abstraction. Currently using POSIX sockets directly (works on both). │ Small — already portable via POSIX │
  ├────────────────────┼─────────────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────┤
  │ OSAL Linux backend │ Unit tests on host without hardware.                                                │ Medium — pthreads mapping          │
  └────────────────────┴─────────────────────────────────────────────────────────────────────────────────────┴────────────────────────────────────┘

  ---
  What Needs to Change for Scale

  1. Component sharing model

  Current: Each ESP-IDF app has its own components/ with duplicate CMakeLists.txt wrappers pointing to lib/.

  Better:

  firmware/
    esp-idf/
      components/              # Shared ESP-IDF components (one copy)
        eai_osal/CMakeLists.txt
        wifi_prov_common/CMakeLists.txt
        eai_log/CMakeLists.txt
      wifi_provision/          # App — EXTRA_COMPONENT_DIRS points to ../components
      osal_tests/              # Tests — same
      wifi_prov_tests/         # Tests — same


  Apps set EXTRA_COMPONENT_DIRS to include the shared components directory. One CMakeLists.txt per component, shared by all apps.

  2. Logging must be abstracted first

  Before writing any new shared library, eai_log needs to exist. Otherwise every library either uses Zephyr logging (not portable) or needs its own shim (doesn't
  scale).

  3. API contracts need formal documentation

  The credential -ENOENT vs -1 bug was caught by tests, but only because we ported the tests. Every shared library API should document its return values in the
  header, and the tests should verify those contracts. This is especially important when multiple backends implement the same API.

  4. Platform test matrix

  We need a clear matrix of what tests run where:

  ┌──────────────────┬───────────────────────┬───────────────────┬───────────────────┐
  │       Test       │       QEMU (CI)       │    ESP32 (HW)     │     nRF (HW)      │
  ├──────────────────┼───────────────────────┼───────────────────┼───────────────────┤
  │ OSAL Zephyr      │ ✅ twister            │ -                 │ ✅ RTT            │
  ├──────────────────┼───────────────────────┼───────────────────┼───────────────────┤
  │ OSAL FreeRTOS    │ -                     │ ✅ Unity          │ -                 │
  ├──────────────────┼───────────────────────┼───────────────────┼───────────────────┤
  │ wifi_prov msg/sm │ ✅ twister            │ ✅ Unity          │ -                 │
  ├──────────────────┼───────────────────────┼───────────────────┼───────────────────┤
  │ wifi_prov cred   │ ✅ twister (Settings) │ ✅ Unity (NVS)    │ -                 │
  ├──────────────────┼───────────────────────┼───────────────────┼───────────────────┤
  │ Integration      │ -                     │ ✅ hw-test-runner │ ✅ hw-test-runner │
  └──────────────────┴───────────────────────┴───────────────────┴───────────────────┘

  Gap: no CI for ESP-IDF tests. Either add ESP32 QEMU support or a hardware-in-loop runner.

  5. Create app template for ESP-IDF

  The zephyr-build.create_app() MCP scaffolds Zephyr apps from templates. We need an equivalent for ESP-IDF — generates the project skeleton with shared component
  references, sdkconfig.defaults, and main.c boilerplate. Right now creating a new ESP-IDF app means copying from wifi_provision/ and gutting it.

  ---
  Summary

  The OSAL architecture works. Compile-time backend dispatch, static allocation, and thin wrappers deliver zero-overhead portability for OS primitives. The WiFi
  provisioning port proved that shared state machines and wire formats can run across RTOSes with identical external behavior.

  The gaps are in peripheral HALs (BLE, WiFi, storage) and developer experience (build system, tooling, templates, CI). The OSAL covers threads/mutexes/queues
  perfectly — it's everything above that layer where we're still writing platform-specific code.

  Next high-leverage move: eai_log + eai_kv + shared components directory. These three changes would make the next ESP-IDF app port significantly cheaper — maybe 60%
   less platform-specific code than this first one.