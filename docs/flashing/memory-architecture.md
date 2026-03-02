# Memory Architecture: MRAM vs OSPI

## Comparison Table

| Property | MRAM | OSPI (External NOR Flash) |
|----------|------|--------------------------|
| **Type** | On-chip Magnetoresistive RAM (NVM) | External NOR Flash via Octal SPI |
| **Size** | 5.5 MB | Up to 512 MB per interface |
| **Base Address** | 0x8000_0000 | OSPI0: 0xA000_0000, OSPI1: 0xC000_0000 |
| **Controller** | Direct memory-mapped | Synopsys DWC SSI (DesignWare) |
| **Bus Width** | 128-bit internal | 1/2/4/8-bit SPI (Octal DDR) |
| **Clock** | 33 MHz | Up to 100 MHz (200 MB/s DDR) |
| **Write Granularity** | 16 bytes (128-bit) | Flash page (256B), sector erase (4-64KB) |
| **Erase Required?** | No — state machine handles transparently | Yes — explicit sector/block erase |
| **Write Speed** | Non-DMA: 0.31 MB/s, DMA: 2.28 MB/s | Page program ~1-3 ms per 256B |
| **Read Speed** | 58-232 MB/s | Up to 200 MB/s (DDR) |
| **Endurance** | >100,000 cycles | ~100,000 erase cycles |
| **ECC** | 16 bits per 128-bit word (built-in) | None at controller level |
| **Concurrent Access** | 4 write masters + unlimited reads | Single-master (APSS must NOT access with RTSS) |
| **XIP Support** | Always (directly mapped) | Yes (continuous transfer / XIP mode) |
| **Encryption** | None at memory level | Dedicated AES engine per OSPI (128-bit, ECB) |
| **A32/M55_HP/M55_HE** | All cores can access | All cores, but NOT concurrently from APSS+RTSS |

## SoC Memory Map

```
Address Range           Size        Description
──────────────────────────────────────────────────
0x0000_0000-0x0003_FFFF   256KB    ITCM (M55 alias) / Boot Reg (A32)
0x0200_0000-0x05FF_FFFF   4MB      SRAM0
0x0800_0000-0x0A7F_FFFF   2.5MB    SRAM1 (E7) / 4MB (E8 at 0x0240_0000)
0x4000_0000-0x4FFF_FFFF   ---      Peripheral space
0x5000_0000               256KB    SRAM2 (M55_HP ITCM backing)
0x5080_0000               1MB      SRAM3 (M55_HP DTCM backing)
0x5800_0000               256KB    SRAM4 (M55_HE ITCM backing)
0x5880_0000               256KB    SRAM5 (M55_HE DTCM backing)
0x6000_0000-0x63FF_FFFF   ~5MB     SRAM6-9 (E7 only, removed on E8)
0x8000_0000-0x805F_FFFF   5.5MB    MRAM (non-volatile)
0x8058_0000               ---      System Partition (STOC/SERAM)
0x8300_0000               4KB      OSPI0 registers
0x8300_1000               4KB      AES0 registers
0x8300_2000               4KB      OSPI1 registers
0x8300_3000               4KB      AES1 registers
0xA000_0000-0xBFFF_FFFF   512MB    OSPI0 XIP window (HyperRAM)
0xC000_0000-0xDFFF_FFFF   512MB    OSPI1 XIP window (NOR Flash)
```

## MRAM Details

MRAM uses magnetic tunnel junctions — no bulk erase required. The internal state machine handles erase/program per 16-byte block transparently to the CPU. From software's perspective, MRAM behaves like RAM with persistence.

**Programming from software:** A simple memory store instruction. For bulk writes, DMA (up to 128 bytes/cycle) improves throughput ~7x.

**MRAM layout (Application region):**

| Region | Address | Size |
|--------|---------|------|
| Application MRAM | 0x8000_0000 | ~5.5 MB |
| System Partition | 0x8058_0000 | Reserved (STOC, SES firmware) |
| STOC Pointer | 0x805F_FFFC | 4 bytes (last word) |

**Write constraints:**
- Minimum 16-byte aligned writes (128-bit word)
- Up to 4 concurrent write masters
- 2x 16-byte read cache for concurrent reads during writes

## OSPI Details

The Synopsys DWC SSI controller supports Standard/Dual/Quad/Octal SPI in SDR and DDR modes, plus HyperBus protocol for HyperRAM.

**Two independent instances:**
- OSPI0 (0xA000_0000): HyperRAM on DevKit boards
- OSPI1 (0xC000_0000): ISSI IS25WX256 NOR Flash

**Programming OSPI flash requires (unlike MRAM):**
1. Exit XIP mode
2. Write Enable command
3. Sector erase (4KB/32KB/64KB)
4. Wait for erase completion (poll status register)
5. Page program (up to 256 bytes)
6. Wait for program completion
7. Re-enter XIP mode

**AES decryption:** Each OSPI has a dedicated AES engine — 128-bit key, ECB mode, zero additional latency. Allows encrypted firmware on external flash with transparent decryption during XIP.

**Critical constraint:** APSS (A32) must NEVER access OSPI concurrently with RTSS-HP or RTSS-HE. Hardware limitation — concurrent access causes undefined behavior.

## Image Configurations (Boot Paths)

### MRAM-Only (TINY_IMAGE / BASE_IMAGE)

```
MRAM (5.5MB @ 0x8000_0000):
├── ATOC                    0x8000_0000
├── bl32.bin (~30KB)        0x8000_2000
├── devkit-e8.dtb           0x8001_0000
├── xipImage (~3.0MB)       0x8002_0000  ← Kernel XIP
└── cramfs-xip (~1.8MB)     0x8038_0000  ← Rootfs XIP

RAM: Stitched SRAM (4MB + 2.5MB = ~6.5MB)
```

### OSPI Boot (BASE_IMAGE3 — kernel + rootfs on OSPI)

```
MRAM:
├── ATOC                    0x8000_0000
├── bl32.bin (~30KB)        0x8000_2000
└── devkit-e8.dtb           0x8001_0000

OSPI1 NOR Flash:
├── cramfs rootfs           0xC000_0000  ← Rootfs XIP
└── xipImage (~3.6MB)       0xC080_0000  ← Kernel XIP

RAM: HyperRAM (64MB) + Stitched SRAM (~8MB) = ~72MB
```

### SD Card (BASE_IMAGE4)

```
MRAM:
├── ATOC + bl32 + DTB + xipImage

SD Card:
└── ext4 rootfs (partition 2)

RAM: HyperRAM + Stitched SRAM = ~72MB
```

## Flash Chip: ISSI IS25WX256

- 256 Mbit (32 MB) Octal SPI NOR Flash
- XIP base: 0xC000_0000 (OSPI1)
- Page size: 256 bytes
- Sector erase: 4KB (0x21), 32KB (0x5C), 64KB (0xDC)
- Chip erase: 0xC7 / 0x60
- Supports DDR Octal I/O at 100 MHz = 200 MB/s read
- Default wait cycles: 16
