# WiFi Provision on FreeRTOS (ESP-IDF)

Status: In-Progress
Created: 2026-02-16

## Problem

We have a working WiFi provisioning system on Zephyr (`lib/wifi_prov/` + `apps/wifi_provision/`). Our OSAL (`lib/eai_osal/`) claims to enable multi-RTOS portability, but only has a Zephyr backend. We need to build the same WiFi provision app on ESP-IDF/FreeRTOS to:
1. Implement the FreeRTOS OSAL backend (Phase 1.5 from `plans/eai-osal.md`)
2. Discover what the OSAL doesn't cover (peripheral HALs, logging, settings)
3. Validate our code-sharing strategy across build systems
4. Get the same BLE provisioning + WiFi + TCP throughput working on ESP32 DevKitC

## Approach

Rename `zephyr-apps` → `firmware` to reflect multi-RTOS scope, then build an ESP-IDF project that shares portable code (state machine, message codec) and provides ESP-IDF implementations for platform-specific modules.

## Phases

- Phase 0: Rename zephyr-apps → firmware
- Phase 1: OSAL FreeRTOS backend (all 9 primitives)
- Phase 2: ESP-IDF WiFi Provision project
- Phase 3: Integration testing on ESP32 DevKitC
- Phase 4: Unit tests + documentation

## Implementation Notes

(Updated as work progresses)
