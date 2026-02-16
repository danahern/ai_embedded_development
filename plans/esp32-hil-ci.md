# ESP32 Hardware-in-the-Loop CI

Status: In-Progress
Created: 2026-02-16

## Problem

The self-hosted runner (danahern-pc, WSL2) has an ESP32-DevKitC connected via CP2102 (`/dev/ttyUSB0`) alongside the existing nRF5340dk. The hw-test workflow currently only tests nRF, and has stale `zephyr-apps` references (submodule was renamed to `firmware`). We need to: fix the stale paths, install ESP-IDF on the runner, add ESP32 build+flash+boot validation, and do a one-time manual verification.

## Approach

**Single workflow, two independent jobs.** Keep `hw-test.yml` with `nrf-test` and `esp32-test` as separate jobs. Both run on `[self-hosted, hw-test]`, isolated failures, shared concurrency group.

**osal_tests first.** 44 Unity tests with clear pass/fail output (`0 Failures`). No BLE/WiFi dependencies. wifi_provision can be added later.

**Raw CLI in CI (not MCP).** Matches the existing nRF pattern: `idf.py build`, `idf.py flash`, pyserial for serial capture. MCP tools are for interactive sessions.

## Solution

### Phase 0: Runner prerequisites (manual, one-time)

Commands the user runs on the WSL machine:

1. Serial permissions: `sudo usermod -aG dialout danahern` then restart WSL
2. Install ESP-IDF v5.5.2
3. Update runner `.env` (`~/actions-runner/.env`): add `IDF_PATH=/home/danahern/esp/esp-idf`
4. Verify: `source ~/esp/esp-idf/export.sh && idf.py --version`

### Phase 1: Fix stale references in hw-test.yml

- Replace all `zephyr-apps` → `firmware` (paths trigger, submodule checkout, rsync, west build dirs)
- Add workspace migration step (`mv zephyr-apps firmware` if old dir exists)
- Rename job `hw-test` → `nrf-test`
- Move `env:` block into nrf-test job scope

### Phase 2: Add esp32-test job

New job with: ESP-IDF validation, build osal_tests, flash via idf.py, serial capture with pyserial, Unity output verification, artifact upload.

### Phase 3: Manual verification

Trigger workflow_dispatch and verify both jobs pass.

## Implementation Notes

- Serial capture uses inline Python with pyserial (not `idf.py monitor`) to avoid ANSI codes
- `timeout 30` as safety net around serial capture
- ESP-IDF workspace cached at `~/ci-workspace/esp-idf-build/` for build artifacts
- osal_tests project at `firmware/esp-idf/osal_tests/` with 44 Unity tests

## Modifications

(none yet)
