---
paths: ["**/alif-e7/**", "**/alif_e7*", "**/appkit-e7*", "**/linux-boot-e7*"]
---

# Alif E7 AppKit Hardware Rules

## JLink VCOM Requires Active Session (CRITICAL)

The onboard JLink VCOM port (`usbmodem*`) **only produces output during an active JLink debug session**. Without it, the port is completely silent.

**Sequence matters:** Power cycle board FIRST, wait 5+ seconds for boot, THEN start JLink session.

## Probe Serial Numbers

- **Onboard JLink** (VCOM + debug): Serial `001219307699`
- **J-Trace PRO** (external): Serial `001223000022`

## E7 Memory Map (from AUGD0022 / SDK)

| Region | Address | Size |
|--------|---------|------|
| SRAM | 0x02000000 | 8MB |
| MRAM | 0x80000000 | 6MB |
| OSPI1 NOR Flash | 0xC0000000 | up to 1024MB |
| HyperRAM | 0xA0000000 | 64MB |

## E7 MRAM Layout (from official docs)

| Component | File | Address |
|-----------|------|---------|
| TF-A (bl32) | bl32.bin | 0x80002000 |
| DTB | appkit-e7-ospi.dtb | 0x80010000 |
| Kernel (MRAM boot) | xipImage | 0x80020000 |
| Rootfs (MRAM boot) | cramfs-xip | 0x80380000 |

## E7 OSPI Layout (from official docs)

| Component | File | Address |
|-----------|------|---------|
| Rootfs | cramfs-xip | 0xC0000000 |
| Kernel | xipImage | 0xC0800000 |

## E7 Device ID

- Part number in device config: `AE722F80F55D5LS`
- This MUST match the actual SoC — ATOC is silently skipped on mismatch (AUGD0005 p.15)

## E7 Kernel

- Yocto scarthgap branch (kernel 6.12.x)
- MACHINE: `devkit-e8` (shared machine config)

## OSPI Artifact Staging

Flash configs reference `-ospi` suffixed filenames (`xipImage-ospi`, `rootfs-ospi.bin`), but Yocto outputs `xipImage` and `*.cramfs-xip`. Run `stage-ospi.sh` after a Yocto build to copy+rename artifacts.
