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

## Phase 1: SDK Acquisition (Complete)

- [x] 1.1: Clone/Branch Setup — `linux_alif` submodule on `v6.12-dev` (kernel 6.12.6, E8 DTS + defconfigs present). TF-A: same `devkit_e7` platform works for E8.
- [x] 1.2: E8 SETOOLS — Same SETOOLS installation supports E8. Created `firmware/linux/alif-e8/setools/` with `linux-boot-e8.json` ATOC config. E8 part: `AE822FA0E5597`.
- [x] 1.3: E8 Board Profiles — `knowledge/boards/alif_e8_devkit.yml` and `alif_e8_ml_devkit.yml` created.
- [x] 1.4: JLink Device Definitions — `Devices.xml` updated with E8 device (`AE822FA0E5597_M55_HP`). Setup script updated.

Key finding: E8 kernel is in a *different repo* (`alifsemi/linux_alif`) than E7 (`alifsemi/alif_linux`). Kernel for Yocto is fetched by recipe via `ALIF_KERNEL_TREE`/`ALIF_KERNEL_BRANCH` (set by orchestrator).

## Phase 2: Linux Bringup (In-Progress)

- [x] 2.1: Yocto Build — `alif-tiny-image` for `MACHINE=devkit-e8` built successfully (scarthgap, 3m15s). Artifacts: bl32.bin (20KB), devkit-e8.dtb (33KB), xipImage (2.9MB), cramfs-xip.img (1.2MB). Kernel XIP at 0x80020000 confirmed.
- [ ] 2.2: ATOC Config and Flash — ATOC package generated (`gen_toc` succeeded). Artifacts staged in `firmware/linux/alif-e8/setools/` and `tools/setools/build/images/`. **Blocked**: E8 hardware not connected (E7 in use). Flash via SE-UART when board available.
- [x] 2.3: TF-A USB PHY — Official Alif TF-A (`alif_lts-v2.10.8`) has NO USB PHY patches. E8 will need the same patches ported from our E7 fork: `service_enable_usb_phy()`, VBAT power control, PHY POR registers, `-mfloat-abi=soft`.
- [ ] 2.4: USB Gadget / ADB — Requires booting E8. meta-eai recipes should work on scarthgap without zeus syntax porting.
- [ ] 2.5: OSPI Boot (stretch) — E8 has proven M55_HE OSPI "burner" firmware (~30 KB/s). Investigate after MRAM boot works.

## Phase 3: Zephyr Bringup

- 3.1: Board Support
- 3.2: Hello World on M55
- 3.3: Dual-OS (Linux A32 + Zephyr M55)

## Phase 4: ML DevKit

- 4.1: Identify ML DevKit Differences
- 4.2: NPU Hello World
- 4.3: Update Board Profile

See full plan details in session transcript.
