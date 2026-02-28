# Gadget / ConfigFS — USB Function Setup

## Summary

The current Alif Linux distribution uses the monolithic `g_serial` kernel gadget driver — not ConfigFS. This provides a simple USB serial gadget (CDC-ACM) that creates `/dev/ttyGS0` on the target and appears as `/dev/ttyACM0` on the host. There is **no ADB, no ECM/RNDIS networking, and no ConfigFS composite gadget support** in the official Yocto layers. Adding these capabilities requires kernel config changes and userspace setup scripts.

## Key Facts

- **Current gadget**: `g_serial` (CONFIG_USB_G_SERIAL=y) — monolithic, not ConfigFS [S04, S11]
- **Target device**: `/dev/ttyGS0` [S11]
- **Host device**: `/dev/ttyACM0` (CDC-ACM class) [S11]
- **USB IDs**: VID=0x0525, PID=0xa4a7 (Linux Foundation defaults) [S11]
- **Product string**: "Gadget Serial v2.4" [S11]
- **No ConfigFS**: CONFIG_USB_CONFIGFS is not set in any config fragment [S04]
- **No ADB**: No adbd recipe, no FunctionFS support [S04, S05]
- **No ECM/RNDIS**: No USB networking gadget configured [S04]
- **No gadget init scripts**: No systemd units or init.d scripts for gadget setup [S04]

## Current Working Configuration

### Kernel Configs (from usb.cfg fragment)

```
CONFIG_USB_DWC3=y
CONFIG_USB_DWC3_GADGET=y
CONFIG_USB_DWC3_ENSEMBLE=y
CONFIG_USB_GADGET=y
CONFIG_USB_GADGET_VBUS_DRAW=2
CONFIG_USB_GADGET_STORAGE_NUM_BUFFERS=2
CONFIG_USB_LIBCOMPOSITE=y
CONFIG_USB_F_ACM=y
CONFIG_USB_U_SERIAL=y
CONFIG_USB_F_SERIAL=y
CONFIG_USB_F_OBEX=y
CONFIG_USB_G_SERIAL=y
```

### Device Detection (host-side dmesg)

```
usb 1-1: New USB device found, idVendor=0525, idProduct=a4a7, bcdDevice= 5.04
usb 1-1: New USB device strings: Mfr=1, Product=2, SerialNumber=0
usb 1-1: Product: Gadget Serial v2.4
usb 1-1: Manufacturer: Linux 5.4.25-00024-g9283a6810958-dirty with dwc3-gadget
cdc_acm 1-1:2.0: ttyACM0: USB ACM device
```

### Physical Connection

USB-B micro cable from "SoC USB" port on DevKit to host USB-A port. [S11]

## UDC Name

The DWC3 gadget registers as UDC with the name derived from its platform device. On APSS-v2.1.0 (DT node `usb-dual@48200000`), the UDC name is **`48200000.usb-dual`**. On v6.12-dev (DT node `usb@48200000`), it would be `48200000.usb`. Verify on target:
```bash
ls /sys/class/udc/
```

## Critical: g_serial Auto-Binds UDC

**Verified gotcha** [S13: Conversation history]: When `CONFIG_USB_G_SERIAL=y` is set (which the Alif defconfig does by default), g_serial auto-binds the UDC at boot. This **prevents any ConfigFS composite gadget** (ADB + CDC-ECM) from binding.

Adding `# CONFIG_USB_G_SERIAL is not set` to a config fragment does NOT reliably override it — `make olddefconfig` re-enables it.

**Fix**: Use `do_configure_append()` (underscore, not colon — OE zeus syntax) to sed it out AFTER all config merging:
```bitbake
do_configure_append() {
    sed -i 's/^CONFIG_USB_G_SERIAL=.*/# CONFIG_USB_G_SERIAL is not set/' ${B}/.config
}
```

## What's Needed for ConfigFS Composite Gadgets

To replace `g_serial` with a flexible ConfigFS-based gadget:

### 1. Kernel Config Changes

Remove monolithic gadget, add ConfigFS. **Important**: Use `CONFIG_USB_CONFIGFS*` options, NOT legacy `CONFIG_USB_FUNCTIONFS` — they are different Kconfig paths.

```
# Remove (via sed, see above):
# CONFIG_USB_G_SERIAL is not set

# Add — ConfigFS gadget driver:
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_SERIAL=y        # For ACM serial
CONFIG_USB_CONFIGFS_ACM=y           # For ACM serial
CONFIG_USB_CONFIGFS_F_FS=y          # For FunctionFS (ADB) — NOT legacy CONFIG_USB_FUNCTIONFS
CONFIG_USB_F_FS=y                   # FunctionFS function driver
CONFIG_USB_CONFIGFS_ECM=y           # For USB Ethernet (ECM)
CONFIG_USB_F_ECM=y                  # ECM function driver
CONFIG_USB_CONFIGFS_RNDIS=y         # For USB Ethernet (RNDIS/Windows)
CONFIG_USB_CONFIGFS_MASS_STORAGE=y  # For mass storage
```

**Don't confuse** `CONFIGFS_FS` (generic ConfigFS filesystem, likely already enabled) with `USB_CONFIGFS` (USB gadget ConfigFS driver).

### 2. ConfigFS Gadget Setup Script

Example init script for ACM serial + ADB:

```bash
#!/bin/sh
GADGET=/sys/kernel/config/usb_gadget/g1

# Create gadget
mkdir -p $GADGET
echo 0x1d6b > $GADGET/idVendor   # Linux Foundation
echo 0x0104 > $GADGET/idProduct  # Composite device
echo 0x0100 > $GADGET/bcdDevice
echo 0x0200 > $GADGET/bcdUSB

# Strings
mkdir -p $GADGET/strings/0x409
echo "AlifSemi" > $GADGET/strings/0x409/manufacturer
echo "Ensemble E7" > $GADGET/strings/0x409/product
echo "0123456789" > $GADGET/strings/0x409/serialnumber

# ACM function
mkdir -p $GADGET/functions/acm.usb0

# Configuration
mkdir -p $GADGET/configs/c.1/strings/0x409
echo "ACM" > $GADGET/configs/c.1/strings/0x409/configuration
echo 120 > $GADGET/configs/c.1/MaxPower
ln -s $GADGET/functions/acm.usb0 $GADGET/configs/c.1/

# Bind to UDC
UDC=$(ls /sys/class/udc/ | head -1)
echo $UDC > $GADGET/UDC
```

### 3. ADB-Specific Setup

ADB requires FunctionFS:

```bash
# Add FunctionFS function
mkdir -p $GADGET/functions/ffs.adb
ln -s $GADGET/functions/ffs.adb $GADGET/configs/c.1/

# Mount FunctionFS before binding UDC
mkdir -p /dev/usb-ffs/adb
mount -t functionfs adb /dev/usb-ffs/adb

# Start adbd (must write descriptors to FunctionFS before UDC bind)
adbd &
sleep 1

# Then bind UDC
echo $UDC > $GADGET/UDC
```

An `adbd` binary must be cross-compiled and included in the rootfs. The Yocto layers do not provide one.

### 4. ECM Ethernet Setup

```bash
mkdir -p $GADGET/functions/ecm.usb0
# Host MAC and device MAC are auto-generated
ln -s $GADGET/functions/ecm.usb0 $GADGET/configs/c.1/

# After UDC bind, configure network on target:
ifconfig usb0 192.168.7.2 netmask 255.255.255.0 up
# Host side: ifconfig usb0 192.168.7.1 netmask 255.255.255.0 up
```

## Host Mode USB Detection

When configured for host mode (usb_host.cfg), the DWC3 registers as an xHCI host controller: [S11]

```
usb 1-1: new high-speed USB device number 7 using xhci-hcd
usb 1-1: New USB device found, idVendor=0781, idProduct=5567, bcdDevice= 1.00
usb 1-1: Product: Cruzer Blade
usb-storage 1-1:1.0: USB Mass Storage device detected
scsi host0: usb-storage 1-1:1.0
sd 0:0:0:0: [sda] 30464000 512-byte logical blocks: (15.6 GB/14.5 GiB)
```

Mass storage appears as `/dev/sda` (or `/dev/sda1` for partitioned devices).

## Yocto Build System Integration

USB gadget mode is enabled through DISTRO_FEATURES: [S04, S05]

| DISTRO_FEATURE | Kernel Fragment | dr_mode | Function |
|---|---|---|---|
| `apss-usb` | usb.cfg | peripheral | g_serial (CDC-ACM) |
| `apss-usb-host` | usb_host.cfg | peripheral* | xHCI + mass storage |
| `apss-usb-boot` | usb_boot.cfg | peripheral* | xHCI + rootfs from /dev/sda1 |

*Note: dr_mode remains "peripheral" in DT even with host config fragments — this is a known bug. [S04]

## ConfigFS Script Gotchas (Verified on Hardware)

1. **Mount configfs first**: The script may run before configfs is available. Add `mount -t configfs none /sys/kernel/config 2>/dev/null` at the top. [S13]
2. **ConfigFS attribute write errors are cosmetic**: Writes to `idVendor`, `idProduct`, MAC addresses may fail with "Invalid argument" but the gadget still binds with defaults (Google VID 0x18d1). [S13]
3. **BusyBox compatibility**: Use `head -n 1` not `head -1`. BusyBox silently rejects the non-POSIX form. [S13]
4. **macOS requires pure CDC-ECM**: macOS has zero RNDIS support (HoRNDIS driver is dead on Big Sur+). Build kernel with `CONFIG_USB_ETH_RNDIS=n` or create pure ECM gadget function. [S13]
5. **ECM hot-swap creates dead data path**: Switching RNDIS→ECM while cable connected fails. Must replug USB cable or do it at boot. [S13]
6. **Dual IP conflict**: If both usb0 (RNDIS) and usb1 (ECM) have 192.168.7.2, kernel routes via usb0. Fix: `ifconfig usb0 0.0.0.0 down` before reconfiguring. [S13]

## Alif-Specific Gadget Limitations

1. **VBUS_DRAW=2**: Very low VBUS draw (2mA) configured — adequate for bus-powered device but minimal [S04]
2. **No OTG support**: dr_mode is always "peripheral" — no role switching. GHWPARAMS0 confirms Device-Only mode (bits 2:0 = 2), no OTG/VBUS detection hardware. [S02, S04, S13]
3. **No remote wakeup**: USB 2.0 LPM explicitly disabled in DT [S02]
4. **RAM constraint**: USB + gadget uses 2556KB of 4096KB SRAM0. Full USB+ConfigFS+ADB adds ~1MB to kernel. With 4MB SRAM, this can cause OOM panic. [S11, S13]

## Open Questions

- ~~What UDC name does the DWC3 register as?~~ Likely `48200000.usb` — needs verification on target
- ~~Are there any Alif-specific gadget limitations?~~ Yes — see above
- ~~What's the tested working ConfigFS sequence?~~ No ConfigFS exists yet — g_serial only
- Can the DWC3 support multiple concurrent gadget functions (composite device)?
- What's the maximum number of endpoints available for gadget functions?
- Does the 4-EP limit (4 IN + 4 OUT) constrain composite gadget configurations?

## Source References

[S02] linux_alif, [S04] meta-alif-ensemble, [S05] meta-alif, [S06] build-setup, [S08] TinyUSB, [S11] Getting Started Guide — See [sources.md](sources.md)
