# ESP-IDF CI Pipeline

Status: Ideation
Created: 2026-02-16

## Problem

We have 66 ESP-IDF tests (44 OSAL + 22 wifi_prov) that only run on real hardware — manually flashed to an ESP32 DevKitC. Zephyr tests run automatically in CI via QEMU. This gap means:

1. **ESP-IDF regressions go undetected** until someone manually tests on hardware
2. **No gate on PRs** for ESP-IDF code changes
3. **Shared library changes** (OSAL, wifi_prov) could break ESP-IDF without anyone knowing

## Approach

Three tiers, implemented incrementally:

### Tier 1: Build-only CI (GitHub Actions hosted runner)

Verify all ESP-IDF projects compile. No hardware needed.

- Install ESP-IDF toolchain in CI (or use Espressif's Docker image `espressif/idf:v5.5`)
- `idf.py set-target esp32 && idf.py build` for each project
- Runs on every PR that touches `lib/` or `esp-idf/`
- Fast gate — catches compile errors, missing includes, API mismatches

### Tier 2: Hardware-in-loop tests (self-hosted runner)

Run Unity tests on real ESP32 connected to `danahern-pc`.

- Flash via `esptool.py` from the self-hosted runner
- Read serial output, parse Unity `PASS`/`FAIL` lines
- Report results back to GitHub Actions
- Runs on PRs that touch OSAL or wifi_prov code
- Requires: ESP32 DevKitC connected via USB to the runner, serial port accessible from WSL2 (via usbipd)

### Tier 3: Integration tests (self-hosted runner + BLE)

Run `hw-test-runner` tests (BLE discover, WiFi provision, TCP throughput) from the runner.

- Requires: Bluetooth adapter on runner, WiFi network, ESP32 DevKitC
- Most complex — BLE scanning from WSL2 may need BlueZ configuration
- Deferred until Tier 1 and 2 are solid

## Open Questions

- Can we use Espressif's QEMU fork for ESP32 to avoid hardware dependency? (Limited feature support — no WiFi/BLE, but OSAL tests might work)
- Should ESP-IDF build CI use the same Docker image as Zephyr CI, or separate?
- How to handle serial port contention if multiple jobs run simultaneously?
