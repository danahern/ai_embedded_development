# Boot Chain

## Power-On to Linux Shell

```
POWER ON / RESET
      │
      ▼
┌─ SESS (Cortex-M0+ Secure Enclave) ──────────────────────────┐
│                                                               │
│  SEROM (ROM bootloader)                                       │
│    1. Enable power domains                                    │
│    2. Initialize firewalls                                    │
│    3. Initialize UART @ 115200                                │
│    4. Initialize CryptoCell CC312                             │
│    5. Wait for MRAM ready                                     │
│    6. Validate & load SERAM (SES firmware)                    │
│       - Two banks (SERAM0/SERAM1) for redundancy              │
│       - Asterisk in SES output marks active bank              │
│                                                               │
│  SES (SERAM firmware)                                         │
│    1. Initialize SoC (clocks, PLLs, peripherals)              │
│    2. Check wakeup source (cold vs warm boot)                 │
│    3. Check maintenance mode                                  │
│    4. Locate STOC → ATOC                                      │
│       - Read last word of MRAM (0x005F_FFFC for 6MB)          │
│       - Value = offset to ATOC within MRAM                    │
│    5. Validate ATOC (device config + image entries)            │
│    6. Process certificate chains per lifecycle state           │
│       - DM LCS: raw loading, no verification                  │
│       - Secure LCS: full certificate chain verification       │
│    7. Configure memory (OSPI, HyperRAM, SRAM stitching)      │
│    8. Load/configure each core per ATOC entries (top→bottom)  │
│    9. Release core resets                                      │
│   10. Start SE services, enter WFI loop                       │
│                                                               │
└──────────────────────┬────────────────────────────────────────┘
                       │
                       ▼
┌─ APSS (Cortex-A32) — BL32 / SP_MIN (TF-A) ──────────────────┐
│                                                               │
│  1. SP_MIN entry (XIP from MRAM @ 0x80002000)                 │
│  2. Initialize GICv2 (interrupt controller)                   │
│  3. Initialize runtime services (PSCI)                        │
│  4. Configure MMU (memory stitching)                          │
│     - Map SRAM0 (4MB @ 0x0200_0000) + SRAM1 (2.5MB)          │
│       as contiguous via MMU page tables                       │
│  5. Enable HyperRAM (OSPI0) if HYPRAM_EN=1                   │
│  6. Enable OSPI1 NOR Flash if FLASH_EN=1                     │
│  7. Exit to Normal World → jump to kernel entry point         │
│                                                               │
└──────────────────────┬────────────────────────────────────────┘
                       │
                       ▼
┌─ Linux Kernel (xipImage) ────────────────────────────────────┐
│                                                               │
│  1. Entry at kernel load address (MRAM or OSPI)               │
│  2. Read DTB from configured address                          │
│  3. Early console on UART2 (earlycon=uart8250,mmio32)         │
│  4. Mount root filesystem (cramfs XIP or SD card)             │
│  5. Init system → shell prompt                                │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

## STOC Location

The SE locates the ATOC through the STOC pointer stored at the last word of MRAM:

```
MRAM (6MB):
┌──────────────────────────┐ 0x8000_0000
│  ATOC + images           │
│  ...                     │
├──────────────────────────┤
│  System Partition         │ 0x8058_0000
│  (STOC, SERAM firmware)  │
├──────────────────────────┤
│  STOC pointer (4 bytes)  │ 0x805F_FFFC  ← Last word
└──────────────────────────┘ 0x8060_0000
```

**STOC pointer rules:**
- Must be nonzero
- Must be <= MRAM_size - 0.5MB
- Must be a multiple of 16
- Points to ATOC offset within MRAM (typically 0x0 = start)

## SE Decision Logic (No ATOC)

```
IF ATOC is present:
    Process ATOC and Boot
ELSE IF (0x80000000 has valid $SP and 0x80000004 has valid $PC):
    Release M55_HE only (NTOC XIP boot)
ELSE:
    Load STOC Debug stub (if present)
```

NTOC images are XIP from MRAM base — only M55_HE can execute these. Not signed by SE Toolkit.

## Core Boot Order

SES processes ATOC entries **in JSON file order** (top to bottom). Each entry specifies:
- `cpu_id`: `A32_0`, `A32_1`, `M55_HP`, `M55_HE`
- `flags`: `load` (copy to RAM), `boot` (start core), `deferred` (skip at boot, process later via runtime service)

### CPU IDs (SE Host Services)

```c
HOST_CPU_0 = 0,   // A32_0
HOST_CPU_1 = 1,   // A32_1
EXTSYS_0   = 2,   // M55_HP
EXTSYS_1   = 3,   // M55_HE
```

### Debug Stubs

If no ATOC is present, SES loads a debug stub for M55_HE automatically. For other cores (A32, M55_HP), debug stubs must be explicitly included in the ATOC. Stubs are denoted by `_DBG` suffix in SES boot log.

## Multi-Core Boot

The ATOC can boot all cores simultaneously:

```json
Entry 1: bl32.bin     → A32    @ 0x80002000 (XIP, secure world)
Entry 2: xipImage     → A32    @ 0x80020000 (XIP, normal world)
Entry 3: rtss_hp.bin  → M55_HP @ 0x50000000 (load to ITCM, boot)
Entry 4: rtss_he.bin  → M55_HE @ 0x58000000 (load to ITCM, boot)
```

### Memory Isolation per Core

| Subsystem | Memory Regions |
|-----------|---------------|
| APSS (A32) | SRAM0 + SRAM1 (stitched) + HyperRAM + MRAM |
| RTSS-HP | ITCM (256KB @ 0x50000000) + DTCM (1MB @ 0x50800000) |
| RTSS-HE | ITCM (256KB @ 0x58000000) + DTCM (256KB @ 0x58800000) |
| SESS | SERAM (isolated, inaccessible to other cores) |

Firewalls configured by SE during boot enforce isolation.

## TF-A (SP_MIN) Critical Build Flags

| Flag | Value | Purpose |
|------|-------|---------|
| `BL32_IN_XIP_MEM` | 1 | Execute in-place from MRAM |
| `BL32_XIP_BASE` | 0x80002000 | XIP address in MRAM |
| `ENABLE_PIE` | 1 | **CRITICAL** — without this, kernel never starts |
| `HYPRAM_EN` | 1 | **CRITICAL** — enables HyperRAM (OSPI0) |
| `FLASH_EN` | 1 | Enable OSPI1 NOR Flash |
| `PRELOADED_BL33_BASE` | 0x80020000 (MRAM) or 0xC0800000 (OSPI) | Kernel entry point |
| `ARM_PRELOADED_DTB_BASE` | 0x80010000 | DTB address in MRAM |
| `ARM_TRUSTED_SRAM_BASE` | 0x08000000 | Base of trusted SRAM |

## SES Boot Status Flags

| Flag | Meaning |
|------|---------|
| `u` | Uncompressed |
| `C` | Compressed |
| `L` | Loaded to RAM |
| `V` | Verified |
| `s` | Skipped |
| `B` | Booted |
| `E` | Encrypted |
| `D` | Deferred |
