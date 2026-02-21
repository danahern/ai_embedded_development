# Alif E7 SETOOLS Setup & First Boot

Status: In-Progress
Created: 2026-02-18

## Problem

The Alif E7 Yocto image build is complete (3384/3384 tasks) with ADB gadget support (`plans/alif-e7-adb-gadget.md`). Build artifacts exist in the Docker volume but the E7 has never booted Linux. Unlike the STM32MP1 (where we `dd` a WIC to SD card), the E7 requires Alif's proprietary SETOOLS to:

1. Generate an ATOC (Application Table of Contents) from a JSON config
2. Write the ATOC + binary images to MRAM via the Secure Enclave's UART

The J-Link can see the SoC but can't connect to A32 cores because the Secure Enclave hasn't booted them yet — SETOOLS must program the ATOC first.

## Approach

**Two directory split:** Tracked config (ATOC JSON, helper scripts) lives in `firmware/linux/alif-e7/setools/` — survives git operations. Proprietary SETOOLS binaries go in `tools/setools/` (already gitignored via `tools/`).

**Phases:**
1. Download & install SETOOLS (manual — registration required)
2. Hardware connection (PRG_USB port, SE-UART + console UART)
3. Copy build artifacts from Docker volume
4. Create ATOC JSON config with correct memory map
5. Generate ATOC & flash via SE-UART
6. Verify Linux boot on serial console
7. Test ADB over USB OTG

## Solution

### SETOOLS Installation

Downloaded Alif Security Toolkit v1.107.00 (macOS arm64) from [alifsemi.com](https://alifsemi.com/support/kits/ensemble-e7devkit/). Extracted to `tools/setools/`. Actual structure (flat, not nested `app-release-exec/`):

```
tools/setools/
  app-gen-toc            # ATOC generator (takes JSON config)
  app-write-mram         # Writes to MRAM via SE-UART (PyInstaller binary)
  maintenance            # SE maintenance/recovery tool
  tools-config           # Device/revision selector
  build/
    config/              # ATOC JSON configs
    images/              # Binary images
  utils/                 # Python utilities (frozen into binaries)
  alif/                  # SE firmware packages per device
```

macOS quarantine removed with `xattr -r -d com.apple.quarantine tools/setools/`.
Device configured as **E7 (AE722F80F55D5LS)** via `tools-config` (option 3). Initially configured as E8 — wrong device, wrong baud rate. SE-UART actual baud rate is **57600** (not 55000 as E7 config claims).

`tools/setools/` is already gitignored (parent `tools/` is gitignored as west-managed).

### Hardware Connection

On the AK-E7-AIML (AI/ML AppKit), the **PRG_USB** port has an on-board J-Link (`J-Link OB-E1-AlifSemi`) providing:
- Board power
- SWD debug access to all cores
- VCOM serial routed to SE-UART (57600 baud)

**PRG_USB has a 2-channel USB-UART bridge:**
- Channel 1: SE-UART (ISP programming, appears as `/dev/cu.usbmodem<JLINK_SERIAL>1`)
- Channel 2: UART4 (Linux console at 115200) — **requires J15 jumpers** (pins 1-3, 2-4)

Without J15 jumpers, only SE-UART appears. UART4 (Linux console, ttyS0) uses P12_1/P12_2 routed through the USB bridge.

For SETOOLS programming: use the JLink VCOM port at 57600 baud.
For Linux console: install J15 jumpers, use second serial port at 115200 baud.

### Memory Map (from devkit-e8.conf)

| Image | MRAM Address | Size (approx) | Source |
|-------|-------------|----------------|--------|
| bl32.bin (TF-A) | 0x80002000 | ~64KB | `BL32_XIP_BASE` |
| devkit-e8.dtb | 0x80010000 | ~32KB | `KERNEL_DTB_ADDR` |
| xipImage | 0x80020000 | ~3.3MB | `XIP_KERNEL_LOAD_ADDR` |
| cramfs-xip rootfs | 0x80380000 | ≤2MB | `KERNEL_MTD_START_ADDR` (BASE_IMAGE=1) |

Total: ~5.4MB of 5.7MB MRAM.

### ATOC JSON Config

`firmware/linux/alif-e7/setools/linux-boot-e7.json` — tracked in git. Copied to `tools/setools/build/config/` before running `app-gen-toc`.

Schema confirmed from SETOOLS User Guide PDF:
- `mramAddress`: absolute MRAM address for XIP placement
- `cpu_id` values: `A32_0`, `A32_1`, `A32_2`, `A32_3`, `M55_HP`, `M55_HE`
- `flags`: `["boot"]` only on TF-A entry (it jumps to kernel via TF-A config)
- `DEVICE` entry required, pointing to `app-device-config.json` (DevKit default included in SETOOLS)
- `signed: false` for development builds

ATOC generation verified — `app-gen-toc` produces correct memory layout (see `build/app-package-map.txt`).

### Flash Workflow

```bash
# 1. Generate ATOC
cd tools/setools
./app-gen-toc -f build/config/linux-boot-e7.json

# 2. Enter maintenance mode programmatically
python3 -c "
import serial, time
ser = serial.Serial('/dev/cu.usbmodem0012193076991', 57600, timeout=0.5)
for cmd in [b'\\x03\\x00\\xfd', b'\\x03\\x16\\xe7', b'\\x03\\x01\\xfc', b'\\x03\\x09\\xf4']:
    ser.write(cmd); time.sleep(0.1)
    if ser.in_waiting: ser.read(ser.in_waiting)
ser.close()
"
sleep 3

# 3. Write ALL images to MRAM (maintenance mode required for full write)
./app-write-mram -v -p -b 57600
```

**Critical flags for `app-write-mram`:**
- `-p` (pad): **Required**. Without it, silent exit on non-16-byte-aligned images.
- `-v` (verbose): Strongly recommended for debugging.
- `-b 57600`: **Required**. Overrides wrong default baud (55000 for E7 config, but SE actually runs 57600).
- `-nr` (no reset): Writes ATOC only, not individual images. Use for ATOC-only updates.

**Maintenance mode is required** for full writes (with individual images). Without it, GET_REVISION returns malformed data (cmd=0xFC) and the tool fails. Use `-nr` to skip GET_REVISION for ATOC-only writes.

### Boot Verification

Monitor Linux console (second serial port) at 115200 baud:
```bash
screen /dev/cu.usbmodem<SECOND_PORT> 115200
```

Expected: SE → TF-A (bl32.bin) → xipImage → Linux init → dropbear SSH + adbd + usb-ecm gadget.

### ADB Test

Connect USB to board's OTG port (separate from PRG_USB):
```bash
adb devices     # Should show: eai-alif-e7-001    device
adb shell       # Root shell
```

## Implementation Notes

- **Missing build artifacts**: The initial Yocto build (3384 tasks) only produced `xipImage` and `devkit-e8.dtb`. The `poky` distro doesn't include TF-A as an image dependency or `cramfs-xip` as an image type — the `apss-tiny` distro does this automatically. Fixed by adding to `local.conf`:
  - `EXTRA_IMAGEDEPENDS:append = " trusted-firmware-a"` — builds bl32.bin
  - `IMAGE_CLASSES += "cramfs-xip"` and `IMAGE_FSTYPES:append = " cramfs-xip"` — builds cramfs-xip rootfs
- **Incremental rebuild**: Only TF-A compilation and cramfs-xip generation are new. Most of the 3384 tasks are cached (sstate). Build succeeded (3431 tasks total, 62 new).
- **cramfs-xip too large with poky distro**: Even bare `core-image-minimal` with `poky` distro produces 8.5MB cramfs-xip (glibc 2.5MB+ + openssl 1.5MB+ + eudev). Doesn't fit in 5.7MB MRAM. Switched to `DISTRO = "apss-tiny"` which uses musl libc + poky-tiny + busybox init — designed specifically for cramfs-xip on MRAM. Result: **1.2MB cramfs-xip** (vs 8.5MB with poky). Total MRAM usage ~4.3MB of 5.7MB.
- **apss-tiny own-mirrors**: The distro inherits `own-mirrors` class but `SOURCE_MIRROR_URL` is unset (normally configured by Alif's build-setup script). Added `INHERIT:remove = "own-mirrors"` to local.conf to fix fetch failures.
- **apss-tiny provides TF-A + cramfs-xip automatically**: Removed manual `EXTRA_IMAGEDEPENDS` and `IMAGE_CLASSES/IMAGE_FSTYPES` additions — apss-tiny handles both natively.

## Files

### Tracked (in git)

| File | Change |
|------|--------|
| `firmware/linux/alif-e7/setools/linux-boot-e7.json` | **New** — ATOC config template |
| `firmware/linux/alif-e7/setools/flash-e7.sh` | **New** — copies artifacts + runs SETOOLS |
| `firmware/linux/alif-e7/setools/README.md` | **New** — SETOOLS setup and usage |
| `firmware/linux/alif-e7/README.md` | Updated flashing section (was TBD) |
| `yocto-build/build-alif-e7/conf/local.conf` | Switched to apss-tiny distro, disabled own-mirrors |
| `knowledge/boards/alif_e7_devkit.yml` | Added SE-UART/PRG_USB connection details |
| `plans/alif-e7-setools.md` | **New** — this plan |
| `plans/alif-e7-adb-gadget.md` | Updated verification notes |

### Untracked (gitignored)

| Path | Contents |
|------|----------|
| `tools/setools/` | Proprietary SETOOLS binaries (downloaded manually) |

## Boot Debugging Progress

### Session 1: ATOC + Initial Flash
- SETOOLS installed, ATOC generated, all images written to MRAM via `app-write-mram`
- SWD debug unlocked via `app-secure-debug`
- A32 stuck at PC=0x800050EC — data abort in TF-A

### Session 2: TF-A Patches
Two TF-A patches applied in Yocto (`devkit_e7_sp_min_setup.c`):
1. Removed PERIPH_CLK_ENA OSPI clock write (register doesn't exist on E7)
2. Removed NPU-HG initialization (not accessible on AK-E7-AIML)

Patched bl32.bin flashed via custom ISP script (`isp_write_image.py`).

### Session 3: Kernel Crash Analysis
- TF-A now boots successfully, kernel starts executing (PC in 0xBFxxxxxx XIP range)
- **Root cause found**: DTB declares 8MB SRAM (`reg = <0x2000000 0x7de000>`) but actual hardware has only 4MB (0x02000000-0x023FFFFF)
- Kernel allocates page tables at 0x027DDC00 (non-existent SRAM)
- Causes double abort: section translation fault → vector page external abort → CPU lockup at 0xFFFF000C
- FC5 firewall reports continuous exceptions, flooding SE-UART
- **DTB patched on disk**: `reg = <0x2000000 0x400000>` (4MB)
- **BLOCKED**: Cannot flash fixed DTB — firewall flood blocks ISP, MRAM write-protected from JLink

### Session 4: First Linux Boot

**Key discoveries:**
1. `app-cpu-stubs.json` (factory test config) flashed — A32 booted stubs successfully. Confirmed device config is essential.
2. **Root cause of all previous boot failures**: `linux-boot-e7.json` was missing the `DEVICE` entry. Without it, SE doesn't configure firewalls/clocks/pins, A32 cores never start.
3. Added `DEVICE` entry to linux-boot-e7.json, regenerated ATOC, did full flash via `app-write-mram -v -p -b 57600` (in maintenance mode).
4. **Linux kernel confirmed running via JLink SWD**: PC=0xBFA3C83C (kernel virtual text), EL1, Non-secure, IRQs enabled, Thumb-2 mode. TF-A handed off correctly.
5. **No console output visible** — UART4 (ttyS0) lines are idle. Default `app-device-config.json` has `"pinmux": []` (empty). Need either: add UART4 pinmux to device config, or install J15 jumpers + rely on kernel pinctrl.
6. **Programmatic maintenance mode works**: START_ISP → SET_MAINTENANCE → STOP_ISP → RESET_DEVICE over SE-UART. No physical button needed.

### Recovery Procedures

**Programmatic (preferred):** Send ISP commands over SE-UART at 57600 baud:
1. START_ISP (0x00) → ACK
2. SET_MAINTENANCE (0x16) → ACK
3. STOP_ISP (0x01) → ACK
4. RESET_DEVICE (0x09) → board reboots into maintenance mode

**Manual (fallback):**
1. Run `./maintenance -d` in tools/setools/
2. Navigate: 1 → Device Control → 1 → Hard maintenance mode
3. **Press physical RESET button** when prompted

## Verification

- [x] SETOOLS installed and `app-gen-toc` runs on macOS
- [x] Device configured as E8 (AE822FA0E5597LS0) via `tools-config`
- [x] Build artifacts copied from Docker volume (bl32.bin, xipImage, appkit-e8.dtb, cramfs-xip)
- [x] ATOC JSON created with correct memory addresses and schema
- [x] `app-gen-toc` generates ATOC successfully (app-package-map.txt verified)
- [x] SE-UART accessible via JLink VCOM at 57600 baud
- [x] `app-write-mram -v -p -b 57600` writes all images to MRAM without errors
- [x] SWD debug unlocked via `app-secure-debug`
- [x] TF-A boots (after PERIPH_CLK_ENA + NPU-HG patches)
- [x] Kernel starts executing (XIP from MRAM at 0x80020000)
- [x] DTB memory fix flashed (4MB SRAM, binary patch at offset 560)
- [x] DEVICE config included in ATOC (app-device-config.json)
- [x] **Linux kernel running** — confirmed via JLink SWD (PC=0xBFxxxxxx, EL1, Non-secure, IRQs on)
- [ ] Serial console shows login prompt (UART4/ttyS0 — needs J15 jumpers or device config pinmux)
- [ ] `adb devices` shows `eai-alif-e7-001` (requires USB OTG cable + ADB in image)

## Risks

- **RESOLVED — ATOC JSON schema**: Confirmed from SETOOLS User Guide.
- **RESOLVED — Device config JSON**: DevKit default `app-device-config.json` included in SETOOLS.
- **RESOLVED — MRAM capacity**: apss-tiny cramfs-xip is 1.2MB. Total ~4.3MB of 5.7MB.
- **RESOLVED — Silent `app-write-mram` crash**: Fixed with `-p` flag.
- **RESOLVED — SE-UART connection**: JLink VCOM provides SE-UART (not separate PRG_USB cable).
- **RESOLVED — TF-A data aborts**: Two patches (PERIPH_CLK_ENA + NPU-HG removal).
- **RESOLVED — DTB SRAM size wrong**: Binary patched from 8MB to 4MB, reflashed.
- **RESOLVED — Board bricked**: Programmatic maintenance mode via ISP commands. No physical button needed.
- **RESOLVED — Missing device config**: ATOC must include DEVICE entry for A32 to boot.
- **RESOLVED — Baud rate mismatch**: E7 config says 55000 but SE actually runs 57600. Use `-b 57600`.
- **CURRENT — No console output**: UART4 lines idle. Need J15 jumpers or UART4 pinmux in device config.
- **ADB not in current build**: apss-tiny cramfs-xip is minimal. ADB requires rebuild with additional packages.
