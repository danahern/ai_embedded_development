# Alif Ensemble E7 Linux Support

Status: In-Progress
Created: 2026-02-17

## Problem

The workspace has mature embedded Linux infrastructure for STM32MP1 (Yocto image builds, Buildroot cross-compilation, Docker containers, linux-build MCP). The Alif E7 DevKit (2x Cortex-A32 + 2x Cortex-M55 + Ethos-U55 NPU) needs the same workflow: Yocto image build, app cross-compilation, deploy/SSH.

Key differences from STM32MP1: proprietary boot chain (SE → TFA → kernel, no U-Boot), XIP kernel from OSPI flash, Cortex-A32 (vs A7).

## Approach

Reuse existing infrastructure where possible. Alif provides official Yocto BSP layers (`meta-alif`, `meta-alif-ensemble`) with scarthgap branches matching our setup.

**Phases:**
1. Yocto layer setup — clone BSP layers, create E7 build config, build `core-image-minimal`
2. Cross-compilation Docker image — lightweight `crossbuild-essential-armhf` (no Buildroot needed)
3. Board-aware Makefiles — `BOARD=alif-e7` variable, default unchanged for STM32MP1
4. Board profile + deployment docs
5. Documentation updates + knowledge capture

**Phase 4 (ADB gadget):** Implemented in `plans/alif-e7-adb-gadget.md`. Kernel bbappend, board-aware gadget script, and build configs are in place. Awaiting build + hardware validation.

## Solution

### Yocto Build Config
- Separate build dir: `yocto-build/build-alif-e7/` (shares poky/meta-oe sstate with STM32MP1)
- Layers: poky + meta-oe + meta-python + meta-filesystems (required by meta-alif) + meta-alif + meta-alif-ensemble
- MACHINE: `devkit-e8` (devkit-e7.conf was archived as `.orig` — E8 supersedes it but still targets E7 hardware via `TF-A_PLATFORM = "devkit_e7"`)
- Same Yocto Docker container (no Dockerfile changes)

### Cross-Compilation
- `firmware/linux/docker/Dockerfile.alif-e7` — Ubuntu 22.04 + `crossbuild-essential-armhf`
- System cross-compiler: `arm-linux-gnueabihf-gcc` (no Buildroot dependency)
- CPU flags: `-mcpu=cortex-a32 -mfpu=neon -mfloat-abi=hard`

### Board-Aware Makefiles
- `BOARD` variable in each app Makefile
- `BOARD=alif-e7`: system cross-compiler + Cortex-A32 flags
- Default (no BOARD): existing Buildroot toolchain + Cortex-A7 flags
- Top-level Makefile passes `BOARD` to sub-makes

## Implementation Notes

- **Machine config naming**: scarthgap branch has `devkit-e8.conf` (active) and `devkit-e7.conf.orig` (archived). The E8 config has 2025 copyright, SMP=1 by default, and reorganized HyperRAM/OSPI logic. E7 config had SMP=0 and simpler memory layout.
- **meta-filesystems required**: meta-alif README lists `meta-filesystems` as a dependency. Already available in our meta-openembedded clone but not included in STM32MP1 bblayers.conf — must be added for E7.
- **No Dockerfile changes for Yocto**: Same `yocto-builder` container works — Alif layers are pure Yocto recipes, no special host dependencies.
- **Lighter cross-compilation image**: E7 uses `crossbuild-essential-armhf` (distro package) instead of Buildroot. Docker image is much smaller (~200MB vs ~2GB after Buildroot build).
- **OSPI boot chain**: Kernel XIP from MRAM at 0x80020000, DTB at 0x80010000. SETOOLS/ATOC needed for packaging — validation requires hardware.

### Files Created
- `yocto-build/build-alif-e7/conf/bblayers.conf`
- `yocto-build/build-alif-e7/conf/local.conf`
- `firmware/linux/docker/Dockerfile.alif-e7`
- `firmware/linux/alif-e7/README.md`
- `knowledge/boards/alif_e7_devkit.yml`
- `plans/alif-e7-linux.md`

### Files Modified
- `firmware/linux/apps/hello/Makefile` — added BOARD=alif-e7 support
- `firmware/linux/apps/rpmsg_echo/Makefile` — added BOARD=alif-e7 support
- `firmware/linux/apps/Makefile` — passes BOARD= to sub-makes
- `firmware/linux/README.md` — covers both STM32MP1 and E7
- `CLAUDE.md` — added E7 to board table + updated Linux workflow
- `claude-mcps/linux-build/CLAUDE.md` — documented multi-board usage

### Knowledge Items Captured
- E7 uses devkit-e8 machine config (not devkit-e7)
- meta-alif requires meta-filesystems
- E7 XIP boot chain (SE → TFA → xipImage)
- Cortex-A32 vs A7 cross-compilation flags

## Modifications

- Phase 4 (ADB gadget) implemented — see `plans/alif-e7-adb-gadget.md`
- Hardware flash/boot validation cannot be done without physical board access
- MACHINE changed from `devkit-e7` to `devkit-e8` after discovering the config was superseded in scarthgap
