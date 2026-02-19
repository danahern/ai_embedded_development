# Embedded Android HAL Library Suite

**Status:** In-Progress
**Created:** 2026-02-19

## Overview

Expand the eai_audio pattern across major Android HAL domains — portable C libraries with compile-time backend dispatch, static allocation, POSIX test stubs.

## Phase 1 — Build Now (demand-driven)

| # | Library | Functions | Tests | Status |
|---|---------|-----------|-------|--------|
| 1 | eai_sensor | 10 | 25 | Complete |
| 2 | eai_display | 12 | 22 | Complete |
| 3 | eai_input | 8 | 17 | Complete |

### Decision Point
After Phase 1, validate with real hardware backends on 2+ platforms. If abstraction saves time, continue. If not, stop and use native APIs.

## Phase 2 — Build When Needed (on-demand)

| Library | Trigger |
|---------|---------|
| eai_camera | When a camera-based app is planned |
| eai_haptics | When haptic feedback is needed |
| eai_periph | When GPIO/I2C/SPI abstraction needed across platforms |
| eai_nn | When on-device inference is needed |
| eai_nfc | When NFC app is planned |
| eai_power/thermal/perf/device | When system management abstraction needed |

## Verification Checklist

- [x] eai_sensor: 25 native tests pass (ASan + UBSan clean)
- [x] eai_display: 22 native tests pass (ASan + UBSan clean)
- [x] eai_input: 17 native tests pass (ASan + UBSan clean)
- [x] API follows unified naming contract
- [x] CLAUDE.md documents all public functions
- [x] No dynamic memory allocation
- [x] All returns: 0 / negative errno / positive count
- [x] Test helpers guarded by backend/test defines
- [x] firmware/lib/CMakeLists.txt and Kconfig updated
