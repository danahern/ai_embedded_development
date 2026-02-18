# STM32MP1 ADB Gadget

Status: Complete
Created: 2026-02-18

## Problem

Need developer-friendly access to the STM32MP1 board over USB: shell, file transfer, port forwarding. SSH over CDC-ECM worked but required IP configuration, DHCP, SSH keys, and host-key workarounds. ADB provides zero-config USB access — plug in, `adb devices`, done.

## Approach

Initially attempted a composite USB gadget (CDC-ECM + FunctionFS/ADB) on the DWC2 OTG controller. This failed due to the DWC2 having limited hardware FIFOs (952 entries) — the combined endpoints of ECM + FFS exceeded available FIFOs, causing a `dma_free_attrs` kernel warning and ECM link failure.

Pivoted to ADB-only gadget, which provides all needed functionality:
- `adb shell` replaces SSH
- `adb push/pull` replaces SCP
- `adb forward` replaces SSH port forwarding

## Solution

### meta-eai Layer (inside Docker volume)

1. **`recipes-kernel/linux/linux-stm32mp_%.bbappend`** — adds `usb-functionfs.cfg` kernel config fragment (`CONFIG_USB_FUNCTIONFS=m`, `CONFIG_USB_FUNCTIONFS_GENERIC=y`)
2. **`recipes-connectivity/usb-ecm/`** — ADB gadget setup script + SysVinit service
3. **`recipes-devtools/android-tools-conf/`** — empty provider satisfying adbd's RDEPENDS (replaces meta-oe's systemd-based version)

### Gadget Setup Script
- Creates configfs gadget with Google VID/PID (0x18d1/0x4e11)
- Single FunctionFS function (`ffs.adb`)
- Mounts FunctionFS at `/dev/usb-ffs/adb`
- Starts adbd before UDC bind (critical ordering)
- Auto-starts at boot via SysVinit (S90)

### Yocto local.conf
```
IMAGE_INSTALL:append = " android-tools-adbd"
PREFERRED_PROVIDER_android-tools-conf = "android-tools-conf"
```

### Host Setup
```bash
brew install android-platform-tools
adb devices    # Shows: eai-stm32mp1-001    device
adb shell      # Root shell on board
```

## Implementation Notes

- **DWC2 FIFO limitation**: Composite gadgets (ECM + FFS) fail on STM32MP1's DWC2 OTG controller. The `dwc2_hsotg_ep_enable: No suitable fifo found` error occurs when too many endpoints are configured. ADB-only uses fewer endpoints and works fine.
- **adbd must start before UDC bind**: FunctionFS endpoints must be opened by adbd before `echo $UDC > UDC`. The script sleeps 2s after starting adbd.
- **android-tools v5.1.1.r37**: Old (Android 5.1 era) but stable on embedded Linux. Uses FunctionFS protocol.
- **adbd bcdVersion warning**: `bcdVersion must be 0x0100, stored in Little Endian order` — cosmetic warning from old adbd, doesn't affect functionality.
- **BusyBox head**: Must use `head -n 1` not `head -1`.
- **configfs not auto-mounted**: Script explicitly mounts configfs.
- **SysVinit not systemd**: meta-oe's adbd service file assumes systemd. We provide our own init script.

## Modifications

- Dropped CDC-ECM from composite gadget due to DWC2 FIFO limits
- Dropped SSH/Dropbear dependency (ADB replaces it for dev access)
- Future: update linux-build MCP to support ADB transport alongside SSH

## Verification

- [x] Kernel builds with FunctionFS module
- [x] ADB gadget creates FFS interface
- [x] adbd starts and opens FFS endpoints
- [x] `adb devices` on Mac sees `eai-stm32mp1-001`
- [x] `adb shell` gives root shell (`uname -a` returns Linux 6.6.78)
- [x] `adb push/pull` transfers files
- [x] No DMA warnings or kernel crashes with ADB-only gadget
