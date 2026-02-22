# Alif E7 AppKit — Learnings

Hard-won knowledge from bringing up Linux on the AK-E7-AIML AppKit (AE722F80F55D5LS).

## Board Overview

- **SoC**: Alif Ensemble E7 (AE722F80F55D5LS)
- **Cores**: 2x Cortex-A32, 2x Cortex-M55 (HP/HE), Ethos-U55 NPU
- **MRAM**: 5.5MB at 0x80000000–0x80580000 (non-volatile, no erase needed)
- **SRAM**: 4MB at 0x02000000–0x023FFFFF
- **HyperRAM**: 2.5MB stitch at 0x08000000 (when enabled)
- **Console**: UART2 at 0x4901A000, 115200 baud (J15 jumper position 5-7/6-8)
- **Debug**: On-board J-Link OB-E1-AlifSemi via PRG_USB

## Boot Chain

```
Secure Enclave (SE) → TF-A (SP_MIN v2.1) → Linux 5.4.25 → cramfs rootfs → /sbin/init → root shell
```

The SE controls everything. It reads the ATOC from system MRAM, applies device config (pinmux, clocks, firewalls), then boots the A32 core with TF-A. There is no U-Boot.

## MRAM Layout

| Component | File | Address | Typical Size |
|-----------|------|---------|-------------|
| ATOC | AppTocPackage.bin | System MRAM (~0x8057xxxx) | ~7 KB |
| TF-A | bl32.bin | 0x80002000 | ~26 KB |
| DTB | appkit-e7.dtb | 0x80010000 | ~31 KB |
| Kernel | xipImage | 0x80020000 | ~2.2 MB |
| Rootfs | cramfs-xip | 0x80300000 | ~1.4 MB |

The kernel runs XIP directly from MRAM. Root filesystem is cramfs mounted readonly from physmap-flash.

## Flashing Methods

### J-Link loadbin (preferred — fast)

**Speed**: ~44 KB/s, all 4 images in ~78 seconds (9x faster than SE-UART).

Uses JLinkExe `loadbin` to write directly to MRAM through the M55_HP debug port (AP[3]). MRAM is memory-mapped and doesn't need a flash algorithm — plain memory writes work.

**Setup** (one-time):
```bash
# Install device definition + JLinkScript
claude-mcps/alif-flash/jlink/setup.sh

# Or via MCP:
alif-flash.jlink_setup(install=true)
```

This installs two files to `~/Library/Application Support/SEGGER/JLinkDevices/AlifSemi/`:
- `Devices.xml` — defines `AE722F80F55D5_M55_HP` device (Cortex-M55 core)
- `AlifE7.JLinkScript` — overrides `ResetTarget()` to prevent reset

**Usage** (MCP tool):
```
alif-flash.jlink_flash(config="/path/to/linux-boot-e7.json", verify=true)
# Then power cycle board
```

**Usage** (standalone script):
```bash
claude-mcps/alif-flash/jlink/flash-mram.sh -v /path/to/images/
# Then power cycle board
```

**Usage** (raw JLinkExe):
```bash
JLinkExe -device AE722F80F55D5_M55_HP -if SWD -speed 4000 -autoconnect 1 -NoGui 1
J-Link> loadbin /path/to/bl32.bin 0x80002000
J-Link> loadbin /path/to/dtb.bin 0x80010000
J-Link> loadbin /path/to/xipImage.bin 0x80020000
J-Link> loadbin /path/to/rootfs.bin 0x80300000
```

**Important flags**:
- `-NoGui 1` — Without this, JLinkExe can pop open a GUI probe selector dialog on macOS. Always include it.
- `-autoconnect 1` — Automatically connects to the first available probe.

**Multiple writes per session**: You don't need to power cycle between individual `loadbin` commands. All 4 images can be written in a single JLinkExe session. Only power cycle before the first connection (to ensure AP[3] is alive) and after you're done (to trigger SE boot).

**MRAM alignment**: MRAM requires 128-bit aligned writes, but `loadbin` handles this transparently — no special action needed.

**Limitation**: J-Link writes images only. It does NOT write the ATOC. You must use SE-UART (`app-write-mram`) at least once to establish the ATOC, then J-Link for fast image updates during development.

### SE-UART ISP (fallback — reliable)

**Speed**: ~5 KB/s at 57600 baud. Full flash of ATOC + 4 images takes ~13.5 minutes.

Uses the proprietary ISP protocol over the SE-UART header (FTDI adapter, `/dev/cu.usbserial-*`).

```
alif-flash.maintenance()     # Enter maintenance mode
alif-flash.gen_toc(config="build/config/linux-boot-e7.json")
alif-flash.flash(config="/path/to/linux-boot-e7.json")
```

Required for initial ATOC setup or if J-Link is unavailable.

## Critical Gotchas

### JLinkScript is mandatory

`loadbin` performs an "implicit reset & halt of MCU" before writing. On the Alif E7, any SWD reset kills the SE boot sequence — AP[3] (M55_HP) disappears and memory access fails. The `AlifE7.JLinkScript` overrides `ResetTarget()` to a no-op, preventing this.

Without the JLinkScript:
```
loadbin /path/to/file.bin 0x80002000
→ Reset, AP[3] gone, "Could not find core in CoreSight setup" error
```

### JLinkExe rejects non-.bin file extensions

`loadbin` silently rejects files with extensions like `.dtb`, `.img`, `.cramfs-xip`, or no extension (`xipImage`). Error: "File is of unknown / unsupported format." Only `.bin` works.

**Workaround**: Copy files to temp `.bin` before loading. The `jlink.py` module does this automatically. The standalone `flash-mram.sh` script does NOT — it will fail on non-`.bin` files. If using the shell script, rename files manually.

`verifybin` has the same extension sensitivity — the temp-`.bin` rename is needed for verify too.

### Power cycle required after flash

A JLink reset does NOT trigger the SE boot sequence. After flashing, you must physically unplug and replug the PRG_USB cable. The SE then reads the ATOC, initializes clocks/peripherals, and boots TF-A → Linux.

### Power cycle required before J-Link connection

If AP[3] has been disrupted (by a prior reset, failed connection, etc.), the M55_HP core is gone. Power cycle the board to restore the SE boot state and make AP[3] available again.

### "Failed to halt CPU" warnings are harmless

JLinkExe prints `"****** Error: Failed to halt CPU."` between `loadbin` operations. This is because the M55_HP core is running SE firmware and can't be halted — but MRAM writes succeed regardless. These warnings are cosmetic.

### ATOC lives in system MRAM, not 0x80000000

The SE reads the ATOC from system MRAM (~0x8057xxxx), NOT from 0x80000000 (APP MRAM base). Writing `AppTocPackage.bin` to 0x80000000 does nothing. The `app-write-mram` tool knows the correct system MRAM addresses.

### Use the correct DTB

The `alif_linux` repo (branch `devkit-b0-5.4.y`) has multiple DTS files. Only `appkit-e7-flatboard.dts` works:

- `appkit-e7.dts` — WRONG: `compatible = "arm,Appkit-E7"`, wrong clock speeds
- `appkit-e7-flatboard.dts` — CORRECT: `compatible = "alif,ensemble"`, CPU 800MHz

The kernel has `DT_MACHINE_START` for `"alif,ensemble"` only. Wrong DTB causes immediate panic.

### Use devkit-ex-b0 branch, NOT scarthgap

`meta-alif-ensemble` branch `scarthgap` has NO `appkit-e7.conf` — only `appkit-e8.conf` which targets different hardware. TF-A from scarthgap crashes on E7 AppKit due to different SRAM base address, missing PIE, and wrong variable names.

| Setting | devkit-ex-b0 (correct) | scarthgap (wrong) |
|---------|----------------------|-------------------|
| HyperRAM enable | `HYPRAM_EN` | `AP_HYPERRAM_EN` |
| Trusted SRAM | `0x08000000` | `0x027DE000` |
| PIE | `ENABLE_PIE=1` | not set |
| Rootfs address | `0x80300000` | `0x80380000` |

### SE-UART baud rate is 57600

The SE-UART ISP protocol runs at 57600, set in `isp_config_data.cfg`. This is the FTDI adapter baud rate. The Linux console UART2 runs at 115200 — different port, different baud.

### SE-UART ISP needs chunked writes

Large MRAM writes (>256KB) cause FTDI USB adapter drops. The alif-flash MCP works around this with 256KB chunked segments with reconnect-on-drop logic.

## Debug Access Points

The J-Link sees 5 Access Ports:

| AP | Type | Target | Notes |
|----|------|--------|-------|
| AP[0] | AHB-AP | M55_HE | Not always accessible |
| AP[1] | APB-AP | Debug | CoreSight debug infra |
| AP[2] | AXI-AP | System bus | Memory access, no CPU |
| AP[3] | AHB-AP | M55_HP | **Used for MRAM programming** |
| AP[4] | AHB-AP | (varies) | Additional core |

JLinkExe connects to AP[3] via the `AE722F80F55D5_M55_HP` device definition. The `-autoconnect 1` flag handles the AP selection automatically.

## Serial Ports (macOS)

| Port Pattern | Source | Use | Baud |
|-------------|--------|-----|------|
| `/dev/cu.usbserial-*` | External FTDI adapter | SE-UART ISP flash | 57600 |
| `/dev/cu.usbmodem*` | On-board J-Link VCOM | Console (UART2 via J15) | 115200 |

Always use `usbserial` (FTDI) for ISP operations. The J-Link VCOM routes through J15 and shows console output at 115200.

## Linux Boot Details

Once booted:
- Memory: ~6.5 KB total (4MB SRAM + 2.5MB HyperRAM stitch), ~6 MB available
- Timer: arch_sys_counter at 100MHz, 200 BogoMIPS
- Single CPU active (SMP configured for 2 but only 1 started)
- cramfs rootfs mounted readonly from physmap-flash
- Login: `root`, no password
- Minor: sysfs mount may fail if `CONFIG_SYSFS` not enabled

## File Locations

```
claude-mcps/alif-flash/
├── jlink/
│   ├── Devices.xml           # J-Link device definition
│   ├── AlifE7.JLinkScript    # ResetTarget() override
│   ├── flash-mram.sh         # Standalone flash script
│   └── setup.sh              # One-time installer
├── src/alif_flash/
│   ├── jlink.py              # J-Link flash module (MCP)
│   ├── isp.py                # SE-UART ISP protocol
│   └── server.py             # MCP server (both tools)
└── tests/
    ├── test_jlink.py          # 18 tests
    └── test_isp.py            # 18 tests

tools/setools/build/
├── config/
│   └── linux-boot-e7.json    # ATOC config (image paths + addresses)
└── images/                   # Pre-built Linux images

docs/alif-e7/
└── AUGD00013-*.pdf           # Alif getting started guide
```

## J-Link Approaches That Failed

Things we tried that didn't work, saved here so nobody wastes time on them again.

### Ensemble.FLM flash algorithm

The Alif CMSIS pack includes `Ensemble.FLM` — a flash programming algorithm for J-Link. When referenced via `FlashBankInfo` in `Devices.xml`, JLinkExe tries to use it for `loadbin` writes. It fails with a `GetSectorInfo` error on JLink V8.70. Removed `FlashBankInfo` entirely — MRAM doesn't need a flash algorithm since it's directly memory-writable (no erase cycles).

### AXI-AP (AP[2]) direct memory access

Tried routing writes through the AXI-AP (system bus, AP[2]) using `CORESIGHT_IndexAHBAPToUse = 2` in the JLinkScript. This would avoid needing a CPU core. Doesn't work — JLinkExe requires an AHB-AP with a real CPU core for `loadbin`. The AXI-AP has no associated processor and JLinkExe refuses to use it.

### JFlash GUI

JFlash.app exists on macOS but is GUI-only. Alif was not in the JFlash MCU database at V8.70 — SEGGER's knowledge base says V8.86+ adds Alif E7 support. Even if available, the GUI workflow isn't automatable. JLinkExe with command scripts is the right approach.

### connect-under-reset

Using `connect -cUR` (connect under reset) disrupts the SE boot sequence the same way a normal reset does. AP[3] disappears and the M55_HP core is inaccessible. The only recovery is a full power cycle (unplug/replug PRG_USB). The no-reset JLinkScript approach avoids this entirely.

## Quick Reference

```bash
# One-time setup
claude-mcps/alif-flash/jlink/setup.sh

# Flash all images via MCP (preferred)
alif-flash.jlink_flash(config="/path/to/linux-boot-e7.json", verify=true)
# → Power cycle board

# Flash single component
alif-flash.jlink_flash(image_dir="/path/to/images", components=["kernel"], verify=true)
# → Power cycle board

# First-ever flash (needs ATOC)
alif-flash.maintenance()
alif-flash.flash(config="/path/to/linux-boot-e7.json")
# → Power cycle board
# Then use J-Link for subsequent updates
```
