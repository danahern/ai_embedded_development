# ATOC Reference

## JSON Configuration Format

Each ATOC entry (image object) supports:

| Field | Required | Description |
|-------|----------|-------------|
| `binary` | Yes | Filename in `build/images/` |
| `version` | No | Format `X.Y.Z` |
| `cpu_id` | No | `A32_0`, `A32_1`, `M55_HP`, `M55_HE` |
| `loadAddress` | If LOAD flag | RAM address for execution (hex) |
| `mramAddress` | No | Fixed MRAM placement (hex, >= 0x80000100, 16-byte aligned) |
| `flags` | No | Array: `load`, `boot`, `encrypt`, `compress`, `deferred` |
| `signed` | No | `true`/`false` (default: signed) |
| `disabled` | No | Temporarily exclude without deleting entry |

### Flag Meanings

| Flag | Effect |
|------|--------|
| `load` | Copy image from MRAM to `loadAddress` in RAM |
| `boot` | Start the specified CPU after loading |
| `encrypt` | Image will be encrypted |
| `compress` | Image will be compressed |
| `deferred` | Skip at boot, process later via `SERVICES_boot_process_toc_entry` |

### Image Modes

- **XIP from MRAM**: `mramAddress` set, no `load` flag — CPU executes directly from MRAM
- **Copy to RAM**: `load` + `boot` flags with `loadAddress` — SE copies to RAM, then boots core
- **XIP + Boot**: `mramAddress` + `boot` — execute in-place from MRAM address

## gen_toc Process

```bash
app-gen-toc -f build/config/app-cfg.json
```

**Inputs:**
- JSON config in `build/config/`
- Binary images in `build/images/`
- Device config (`app-device-config.json`) in `build/config/`

**Outputs:**
- `build/AppTocPackage.bin` — ATOC binary package
- `build/AppTocPackage.bin.sign` — ATOC signature (for SE LCS mode)
- `build/app-package-map.txt` — memory map showing layout

**Critical:** `global-cfg.db` must match target device (E7 vs E8). Wrong device → garbled UART, wrong clocks/pins.

### Maximum 15 TOC entries (`SERVICES_NUMBER_OF_TOC_ENTRIES = 15`).

## Part Number Check

`app-write-mram` probes device Part# via ISP. If `global-cfg.db` part# differs from detected device, a warning is shown. Even if you continue and write, SES skips the ATOC on boot (`BL_TOC_DEVICE_MISMATCH`).

## ATOC Config Inventory

### Linux Boot (E7)

**`linux-boot-e7.json`** — MRAM-only boot
```
DEVICE + TFA@0x80002000 + DTB@0x80010000 + KERNEL@0x80020000 + ROOTFS@0x80300000
```

**`linux-boot-e7-ospi.json`** — OSPI boot with M55_HP debug stub
```
DEVICE + M55_HP_STUB@0x50000000 + TFA@0x80002000 + DTB@0x80010000
```

**`linux-boot-e7-ospi-jlink.json`** — J-Link OSPI debug (NON-PERSISTENT)
```
DTB@0x80010000 + ROOTFS@0xC0000000 + KERNEL@0xC0800000
```

### Linux Boot (E8)

**`linux-boot-e8.json`** — MRAM-only boot
```
DEVICE(E8) + TFA@0x80002000 + DTB(devkit-e8.dtb)@0x80010000 + KERNEL@0x80020000 + ROOTFS@0x80380000
```

### Zephyr (E8)

**`zephyr_e8_rtsshe_common.json`** — Zephyr on M55_HE only
```
Zephyr-RTSS-HE: zephyr_rtsshe.bin → M55_HE @ 0x58000000 [load, boot]
```

**`zephyr_e8_rtsshp_common.json`** — Zephyr on M55_HP only
```
Zephyr-RTSS-HP: zephyr_rtsshp.bin → M55_HP @ 0x50000000 [load, boot]
```

**`zephyr_e8_rtsshe_rtsshp_common.json`** — Dual-core Zephyr
```
Zephyr-RTSS-HE: zephyr_rtsshe.bin → M55_HE @ 0x58000000 [load, boot]
Zephyr-RTSS-HP: zephyr_rtsshp.bin → M55_HP @ 0x50000000 [load, boot]
```

### OSPI Burner

**`RTSS-PC-tool-burner.json`** — Flash tool burner on M55_HE
```
RTSS-HE: E8_dk_PC_Tool_Burner.bin → M55_HE @ 0x58000000 [load, boot]
```

### Multi-Pass OSPI Programming

**`ospi-pass-a-kernel.json`** — Stage kernel + OSPI header in MRAM
**`ospi-pass-b-rootfs1.json`** — Stage rootfs part 1
**`ospi-pass-c-rootfs2.json`** — Stage rootfs part 2

Each pass writes to MRAM. TF-A detects the OSPI magic header (0x4F535049) at 0x8000E000 and programs OSPI on boot.

## Core Load Addresses

| Core | Global Address | TCM Alias | Memory |
|------|---------------|-----------|--------|
| M55_HP | 0x50000000 | 0x00000000 (ITCM) | SRAM2, 256 KB |
| M55_HE | 0x58000000 | 0x00000000 (ITCM) | SRAM4, 256 KB |
| A32 | — | — | Executes from MRAM (XIP) or RAM (loaded) |

The SE loads binaries to the global SRAM address. When the core boots, it sees that memory at 0x00000000 via ITCM aliasing.

## Device Registry (alif-flash)

| Property | E7 | E8 |
|----------|----|----|
| Part number | AE722F80F55D5 | AE822FA0E5597 |
| JLink device | AE722F80F55D5_M55_HP | AE822FA0E5597_M55_HP |
| ISP baud | 57600 | 57600 |
| DTB file | appkit-e7.dtb | devkit-e8.dtb |
| Rootfs address | 0x80300000 | 0x80380000 |
| System MRAM base | 0x80580000 | 0x80580000 |
| global-cfg Revision | B4 | A0 |

## SE Boot Error Codes (Common)

| Code | Name | Cause |
|------|------|-------|
| 0x11 | BL_ERROR_FAILED_TOC_CRC32 | Corrupted ATOC |
| 0x17 | BL_ERROR_ENTRY_NOT_SIGNED | Missing signature in secure LCS |
| 0x20 | BL_TOC_IMAGE_DEVICE_MISMATCH | global-cfg.db part# doesn't match SoC |
| 0x0E | BL_ERROR_SIGNATURE_VERIFY_FAILED | Bad certificate chain |
