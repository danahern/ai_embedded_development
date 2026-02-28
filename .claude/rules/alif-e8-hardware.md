---
paths: ["**/alif-e8/**", "**/alif_e8*", "**/devkit-e8*", "**/linux-boot-e8*"]
---

# Alif E8 DevKit Hardware Rules

## E8 MRAM Layout

| Component | File | Address |
|-----------|------|---------|
| TF-A | bl32.bin | 0x80002000 |
| DTB | devkit-e8.dtb | 0x80010000 |
| Kernel | xipImage | 0x80020000 |
| Rootfs | cramfs-xip.img | 0x80380000 |

Note: Rootfs is at 0x80380000 (E7 is 0x80300000).

## E8 Kernel

- Branch: `v6.12-dev` (kernel 6.12.x)
- Yocto release: scarthgap
- MACHINE: `devkit-e8`
- Defconfig: `devkit_e8_defconfig` (SMP) or `devkit_e8_unicore_defconfig`

## Key Differences from E7

- TF-A platform is still `devkit_e7` (shared)
- Scarthgap Yocto uses `:append` syntax (not `_append`)
- DTB path: `alif/ensemble/devkit/devkit-e8.dtb`
- JLink device name: TBD (from E8 device pack)

## SETOOLS

E8 may need its own SETOOLS installation at `tools/setools-e8/` with E8-specific device configs.
