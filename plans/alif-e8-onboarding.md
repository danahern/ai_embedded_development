# Plan: Alif E8 Onboarding + Multi-Board Scaling

**Status**: In-Progress
**Created**: 2026-02-28

## Context

Bring up Linux + Zephyr on E8 in parallel with E7, fixing scaling issues in our tooling as we go.

## Phase 0: Infrastructure Generalization (Complete)

- [x] 0.1: alif-flash Device Registry — `devices.py` with board-to-config mapping, `device` param on all tools, 107 tests pass
- [x] 0.2: linux-build Board-Aware Docker — `board` param on `start_container`, `image_for_board()`, shared `Dockerfile.alif`, 46 tests pass
- [x] 0.3: Knowledge Rules Factoring — `alif-common.md` + tightened E7 + new E8 rules
- [x] 0.4: Linux App Makefile Board Support — All 3 apps use `$(filter alif-%,$(BOARD))` pattern

## Phase 1: SDK Acquisition

- 1.1: Clone/Branch Setup (kernel v6.12-dev, TF-A check)
- 1.2: E8 SETOOLS (device pack, JLink definitions)
- 1.3: E8 Board Profiles
- 1.4: JLink Device Definitions

## Phase 2: Linux Bringup

- 2.1: Yocto Build (scarthgap, MACHINE=devkit-e8)
- 2.2: ATOC Config and Flash
- 2.3: TF-A USB PHY check
- 2.4: USB Gadget / ADB
- 2.5: OSPI Boot (stretch)

## Phase 3: Zephyr Bringup

- 3.1: Board Support
- 3.2: Hello World on M55
- 3.3: Dual-OS (Linux A32 + Zephyr M55)

## Phase 4: ML DevKit

- 4.1: Identify ML DevKit Differences
- 4.2: NPU Hello World
- 4.3: Update Board Profile

See full plan details in session transcript.
