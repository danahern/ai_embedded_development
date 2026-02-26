# Technical Context: Alif E7 OSPI Boot

## Memory Map

### MRAM (written via SE-UART ISP)
| Component | Address | Size | Notes |
|-----------|---------|------|-------|
| ATOC Package | 0x80000000 | ~2KB | Written by gen_toc + flash |
| TF-A (bl32-ospi.bin) | 0x80002000 | 29KB | Stays in MRAM permanently |
| OSPI Prog Header | 0x8000E000 | 16B | Magic trigger, cleared after use |
| DTB (appkit-e7-ospi.dtb) | 0x80010000 | 31KB | Stays in MRAM permanently |
| Staging Area | 0x80020000 | ~4.4MB | Temporary — holds data for OSPI programming |

### OSPI NOR Flash (programmed by TF-A from MRAM staging)
| Component | Address | Size | Notes |
|-----------|---------|------|-------|
| Rootfs (cramfs-xip) | 0xC0000000 | 6.3MB | Split into 2 MRAM passes |
| Kernel (xipImage) | 0xC0800000 | 2.87MB | Single MRAM pass |

## TF-A OSPI Programmer

16-byte header at MRAM 0x8000E000:
```c
struct ospi_prog_hdr {
    uint32_t magic;      // 0x4F535049 ("OSPI" little-endian)
    uint32_t dest_addr;  // OSPI destination address
    uint32_t length;     // bytes to program
    uint32_t src_addr;   // MRAM source address (always 0x80020000)
};
```

On boot, TF-A checks for magic. If found: exits XIP → erases OSPI sectors → programs pages → re-enters XIP → clears magic → boots Linux.

## Pre-built OSPI Headers

Already exist in `firmware/linux/alif-e7/images/`:

| File | Dest | Size | Purpose |
|------|------|------|---------|
| `ospi-hdr-kernel.bin` | 0xC0800000 | 2,868,804 | Kernel to OSPI |
| `ospi-hdr-rootfs1.bin` | 0xC0000000 | 5,242,880 | Rootfs part 1 (first 5MB) |
| `ospi-hdr-rootfs2.bin` | 0xC0500000 | 1,363,968 | Rootfs part 2 (remaining 1.3MB) |

## Build Artifacts

All in `firmware/linux/alif-e7/images/`:

| File | Size | Purpose |
|------|------|---------|
| `bl32-ospi.bin` | 30KB | TF-A with OSPI addresses (PRELOADED_BL33_BASE=0xC0800000) |
| `appkit-e7-ospi.dtb` | 32KB | DTB for OSPI boot |
| `xipImage-ospi` | 2.87MB | Kernel built for XIP at 0xC0800000 |
| `rootfs-ospi-part1.bin` | 5MB | Rootfs bytes 0-5MB |
| `rootfs-ospi-part2.bin` | 1.36MB | Rootfs bytes 5MB-6.3MB |
| `m55_stub_hp.bin` | 4.4KB | M55_HP stub (keeps core out of LOCKUP) |

## ATOC Config

`firmware/linux/alif-e7/setools/linux-boot-e7-ospi.json`:
- DEVICE config (app-device-config.json)
- M55_HP stub → ITCM 0x50000000 (load + boot)
- TFA → MRAM 0x80002000 (boot on A32)
- DTB → MRAM 0x80010000

## Flash Tools (MCP)

| Tool | Purpose |
|------|---------|
| `alif-flash.gen_toc` | Generate ATOC package from JSON config |
| `alif-flash.maintenance` | Enter SE maintenance mode |
| `alif-flash.flash` | Write ATOC + images to MRAM via SE-UART |
| `alif-flash.probe` | Check SE-UART status |

## SE-UART ISP Protocol

- Port: auto-detected (`/dev/cu.usbmodem*`)
- Board must be in maintenance mode before writing
- Maintenance: power cycle → `alif-flash.maintenance` (or `flash` with `maintenance=true`)
- Each MRAM write: ~5 KB/s via ISP protocol

## Known Issues

- `alif-flash.maintenance` can be unreliable — if it fails, the user can enter maintenance manually (hold BOOT button during power-on, or use SE reset sequence)
- MRAM staging area overlaps kernel/rootfs MRAM addresses — this is fine because OSPI boot doesn't use kernel/rootfs from MRAM
- JLink reset can substitute for manual power cycle in some cases
- After OSPI programming, TF-A re-initializes XIP mode before booting Linux

## UART Console

UART2 is the Linux console (connected via PRG_USB). Monitor for:
- TF-A boot banner
- "OSPI PROG:" messages during programming passes
- Linux kernel boot log
- USB gadget init messages
