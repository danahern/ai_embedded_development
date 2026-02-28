---
paths: ["**/alif-e7/**", "**/alif_e7*", "**/appkit-e7*", "**/linux-boot-e7*"]
---

# Alif E7 AppKit Hardware Rules

## JLink VCOM Requires Active Session (CRITICAL)

The onboard JLink VCOM port (`usbmodem*`) **only produces output during an active JLink debug session**. Without it, the port is completely silent.

**To enable VCOM, run JLinkExe in background with a long sleep:**

```bash
/Applications/SEGGER/JLink/JLinkExe -nogui 1 -if SWD -speed 4000 \
  -device AE722F80F55D5_M55_HP -SelectEmuBySN 001219307699 \
  -AutoConnect 1 -CommandFile /tmp/jlink_persist.jlink &
```

**Sequence matters:** Power cycle board FIRST, wait 5+ seconds for boot, THEN start JLink session.

## Probe Serial Numbers

- **Onboard JLink** (VCOM + debug): Serial `001219307699`
- **J-Trace PRO** (external): Serial `001223000022`

## E7 MRAM Layout

| Component | File | Address |
|-----------|------|---------|
| TF-A | bl32.bin | 0x80002000 |
| DTB | appkit-e7.dtb | 0x80010000 |
| Kernel | xipImage | 0x80020000 |
| Rootfs | cramfs-xip.img | 0x80300000 |

## E7 Kernel

- Branch: `devkit-b0-5.4.y` (kernel 5.4.x)
- Yocto release: zeus (OE 3.0)
- MACHINE: `appkit-e7`
