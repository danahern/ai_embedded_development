# Alif E7 Display Demo

Status: In-Progress
Created: 2026-02-18

## Problem

The E7 DevKit has a CDC200 display controller with 2-lane MIPI DSI driving an ILI9806E panel (480x800), plus a D/AVE 2D GPU — but we've never driven the display. Need to validate the display hardware works and then build a rich UI demo.

Two target cores:
- **A32 (Linux)**: Verify display works via DRM/framebuffer using existing Yocto/Docker/ADB infrastructure
- **M55 (Zephyr)**: LVGL demo with GPU acceleration using Alif's Zephyr SDK

## Approach

Two phases, Linux first to validate hardware, then Zephyr for the richer demo.

| Phase | Target | What | Deliverables |
|-------|--------|------|-------------|
| P1 | A32 Linux | DRM framebuffer test | Kernel config, display_test app, Yocto image with DRM tools |
| P2 | M55 Zephyr | LVGL + D/AVE 2D demo | Separate sdk-alif workspace, display sample build |

## Solution

### Phase 1: Linux Display Demo (A32)

#### 1a. Kernel Display Config

Config fragment `display-drm.cfg` added to meta-eai with DRM/CDC200/MIPI DSI/FB options. Added to `linux-alif_%.bbappend` alongside existing USB gadget fragment. If the defconfig already has these as `=y`, the fragment is a no-op safety net.

#### 1b. Yocto Image Packages

`libdrm libdrm-tests` added to `local.conf` (commented out — apss-tiny cramfs-xip has tight MRAM size constraints). Uncomment when OSPI boot is available. Provides `modetest` for quick DRM enumeration.

#### 1c. Cross-Compiled Display Test App

`firmware/linux/apps/display_test/` — DRM/KMS test pattern app with framebuffer fallback:
1. Opens `/dev/dri/card0`, enumerates connectors/CRTCs/encoders
2. Creates dumb buffer, draws 8-color bars (SMPTE pattern)
3. Sets CRTC mode, holds 10 seconds, restores original
4. Falls back to `/dev/fb0` if DRM unavailable (supports 16/32 bpp)

#### 1d. Docker Image Update

Added `libdrm-dev:armhf` to `Dockerfile.alif-e7` for cross-compilation headers. `crossbuild-essential-armhf` enables multiarch automatically.

#### 1e. Build & Deploy Workflow

```
# Cross-compile display_test
linux-build.start_container(image="alif-e7-sdk")
linux-build.build(container, command="make -C /workspace/firmware/linux/apps/display_test BOARD=alif-e7")
linux-build.collect_artifacts(container, host_path="/tmp/artifacts")

# Deploy and test
linux-build.adb_deploy(file_path="/tmp/artifacts/display_test", remote_path="/tmp/")
linux-build.adb_shell(command="/tmp/display_test")
```

### Phase 2: Zephyr LVGL Demo (M55)

#### 2a. Alif SDK Workspace Setup

The Alif Zephyr SDK (`alifsemi/sdk-alif`) is a Zephyr fork with CDC200 driver, ILI9806E DSI driver, and D/AVE 2D GPU integration. Not compatible with upstream Zephyr — requires separate workspace.

```
mkdir -p ~/alif-zephyr && cd ~/alif-zephyr
west init -m https://github.com/alifsemi/sdk-alif.git --mr v2.1.0
west update
```

#### 2b. Build Display Sample

```
cd ~/alif-zephyr
west build -b alif_e7_dk/m55_hp samples/subsys/display/lvgl
```

#### 2c. Flash via SETOOLS

Uses Alif's proprietary SETOOLS (same as Linux flashing, different ATOC config targeting M55_HP).

#### 2d. Custom LVGL Demo App (stretch goal)

D/AVE 2D GPU-accelerated rendering, touch input (GT911), multi-widget UI.

## Files Modified

### Phase 1

| File | Change |
|------|--------|
| `firmware/linux/yocto/meta-eai/recipes-kernel/linux/linux-alif_%.bbappend` | Added `display-drm.cfg` fragment |
| `firmware/linux/yocto/meta-eai/recipes-kernel/linux/files/display-drm.cfg` | **New** — DRM/CDC200 kernel config |
| `firmware/linux/apps/display_test/Makefile` | **New** — cross-compile with libdrm |
| `firmware/linux/apps/display_test/main.c` | **New** — DRM test pattern app |
| `firmware/linux/apps/Makefile` | Added `display_test` to APPS list |
| `firmware/linux/docker/Dockerfile.alif-e7` | Added `libdrm-dev:armhf` |
| `yocto-build/build-alif-e7/conf/local.conf` | Added `libdrm libdrm-tests` (commented) |
| `plans/alif-e7-display.md` | **New** — this plan |

### Phase 2

| File | Change |
|------|--------|
| `~/alif-zephyr/` | **New** — separate Alif SDK workspace (outside main repo) |

## Implementation Notes

- **Yocto local.conf packages commented out**: apss-tiny distro produces cramfs-xip for MRAM (5.7MB limit). Adding libdrm would push past capacity. Left as commented reference for when OSPI boot enables larger rootfs.
- **Alif SDK is a Zephyr fork**: `sdk-alif` pulls `alifsemi/zephyr_alif` instead of upstream `zephyr`. CDC200 driver, ILI9806E panel driver, and D/AVE 2D integration haven't been upstreamed. Two `west`-managed Zephyr trees would conflict, hence separate workspace.

## Risks

1. **Kernel DRM driver may not exist**: Alif BSP kernel may not have DRM driver for CDC200 — could use raw framebuffer. App handles both paths.
2. **MIPI DSI panel init sequence**: ILI9806E needs specific DSI command-mode init. Must be in kernel driver or DTS.
3. **Display not routed in device tree**: DTS must connect CDC200 → DSI host → ILI9806E with correct timing.
4. **Alif SDK workspace size**: `west update` may pull many GB.
5. **SETOOLS dependency**: M55 flashing requires proprietary SETOOLS.

## Verification

### Phase 1
- [ ] Kernel `.config` includes DRM + CDC200 + MIPI DSI support
- [ ] Docker image builds with `libdrm-dev:armhf`
- [ ] `display_test` cross-compiles successfully
- [ ] `modetest -M <driver>` on hardware enumerates the DSI connector
- [ ] Test pattern visible on the ILI9806E panel
- [ ] `display_test` app shows color bars on screen

### Phase 2
- [ ] `west init` + `west update` for sdk-alif succeeds
- [ ] Display sample builds for `alif_e7_dk/m55_hp`
- [ ] LVGL sample builds for `alif_e7_dk/m55_hp`
- [ ] Flash to M55 via SETOOLS succeeds
- [ ] LVGL UI renders on the display
