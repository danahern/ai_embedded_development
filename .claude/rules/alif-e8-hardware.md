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

- **Repo**: `alifsemi/linux_alif` (NOT `alif_linux` — different repo from E7!)
- Branch: `v6.12-dev` (kernel 6.12.6)
- Submodule: `linux_alif/` at workspace root
- Yocto release: scarthgap
- MACHINE: `devkit-e8`
- Defconfig: `devkit_e8_defconfig` (SMP) or `devkit_e8_unicore_defconfig`

## E8 Silicon

- Part number: `AE822FA0E5597` (E7: `AE722F80F55D5`)
- JLink device: `AE822FA0E5597_M55_HP`
- SE firmware packages: `SP-AE822FA0E5597BS0`, `SP-AE822FA0E5597LS0`

## Key Differences from E7

- TF-A platform is still `devkit_e7` (shared)
- Scarthgap Yocto uses `:append` syntax (not `_append`)
- DTB path: `alif/ensemble/devkit/devkit-e8.dtb`
- Kernel repo is `linux_alif` (E7 uses `alif_linux`)

## TF-A

- Same `devkit_e7` platform as E7 (shared TF-A)
- Official Alif TF-A (`alif_lts-v2.10.8`) has NO USB PHY patches
- E8 needs same patches ported from our E7 fork: `service_enable_usb_phy()`, VBAT power control, PHY POR, `-mfloat-abi=soft`

## SETOOLS

Same `tools/setools/` installation supports both E7 and E8. Use `tools-config` to select E8 device.
ATOC config: `firmware/linux/alif-e8/setools/linux-boot-e8.json`.
Device config: `app-device-config-e8.json` (derived from E7, device ID changed to `AE822FA0E5597LS0`).
