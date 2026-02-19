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

Download Alif Security Toolkit v1.109.00 (macOS) from [alifsemi.com/support/kits/ensemble-e7devkit/](https://alifsemi.com/support/kits/ensemble-e7devkit/). Extract to `tools/setools/`. Expected structure:

```
tools/setools/
  app-release-exec/
    app-gen-toc            # ATOC generator (takes JSON config)
    app-write-mram         # Writes to MRAM via SE-UART
    isp_config_data.cfg    # Serial port config
    build/
      config/              # ATOC JSON configs
      images/              # Binary images
```

`tools/setools/` is already gitignored (parent `tools/` is gitignored as west-managed).

### Hardware Connection

Connect micro-USB to **PRG_USB** port (closest to board corner). Provides:
- Power to the board
- Two serial ports via USB-serial:
  - **First port** = SE-UART (programming via SETOOLS)
  - **Second port** = UART2 (Linux console, 115200 baud)

DevKit jumper J26: connect pins 1-3 and 2-4 for serial communication.

Identify ports: `ls /dev/cu.usbmodem*` or `ls /dev/cu.usbserial*`

### Memory Map (from devkit-e8.conf)

| Image | MRAM Address | Size (approx) | Source |
|-------|-------------|----------------|--------|
| bl32.bin (TF-A) | 0x80002000 | ~64KB | `BL32_XIP_BASE` |
| devkit-e8.dtb | 0x80010000 | ~32KB | `KERNEL_DTB_ADDR` |
| xipImage | 0x80020000 | ~3.3MB | `XIP_KERNEL_LOAD_ADDR` |
| cramfs-xip rootfs | 0x80380000 | ≤2MB | `KERNEL_MTD_START_ADDR` (BASE_IMAGE=1) |

Total: ~5.4MB of 5.7MB MRAM.

### ATOC JSON Config

`firmware/linux/alif-e7/setools/linux-boot-e7.json` — tracked in git. Copied to `tools/setools/app-release-exec/build/config/` before running `app-gen-toc`.

**Note:** The exact JSON schema (field names, cpu_id values for A32 cores) will be confirmed from SETOOLS documentation. The M55 example uses:
```json
{
  "HP_APP": {
    "binary": "mram.bin",
    "mramAddress": "0x80001000",
    "cpu_id": "M55_HP",
    "flags": ["boot"],
    "signed": false
  }
}
```

For Linux, the A32 cpu_id is likely `A32_0` or `APSS`, and bl32.bin needs the `boot` flag. May also need a device configuration JSON for clock/pin settings — SETOOLS package likely includes a DevKit default.

### Flash Workflow

```bash
# 1. Copy config and artifacts into SETOOLS tree
firmware/linux/alif-e7/setools/flash-e7.sh

# 2. Generate ATOC
cd tools/setools/app-release-exec
./app-gen-toc -f build/config/linux-boot-e7.json

# 3. Write to MRAM via SE-UART
./app-write-mram -d
```

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

## Verification

- [ ] SETOOLS installed and `app-gen-toc` runs on macOS
- [ ] Serial ports enumerated (SE-UART + console)
- [ ] `isp_config_data.cfg` configured with correct port
- [ ] Build artifacts copied from Docker volume
- [ ] ATOC JSON created with correct memory addresses
- [ ] `app-gen-toc` generates ATOC successfully
- [ ] `app-write-mram` writes to MRAM without errors
- [ ] Linux boots (TF-A → kernel → init)
- [ ] Serial console shows login prompt
- [ ] `adb devices` shows `eai-alif-e7-001`
- [ ] `adb shell` works

## Risks

- **ATOC JSON schema uncertainty**: Exact field names and cpu_id for A32 cores inferred from M55 examples. SETOOLS download includes docs that should clarify. May need iteration.
- **Device config JSON**: ATOC has two parts — device config (clocks, pins, firewalls) and application images. May need separate device config JSON, or DevKit default may work.
- **MRAM capacity**: Resolved — apss-tiny cramfs-xip is 1.2MB. Total ~4.3MB of 5.7MB MRAM (1.4MB headroom).
- **macOS serial driver**: Modern macOS (14+) has built-in FTDI support. If DevKit uses different USB-serial chip, may need driver.
- **First boot ever**: Any boot chain issue (TF-A config, DTB, kernel cmdline) requires debugging with limited visibility (serial console only).
- **SE-UART exclusivity**: Only one process can use SE-UART at a time. Close terminal sessions on that port before running `app-write-mram`.
