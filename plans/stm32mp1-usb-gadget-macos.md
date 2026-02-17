# STM32MP1 USB Gadget Networking for macOS

Status: Planned
Created: 2026-02-16

## Problem

The STM32MP157C-DK2 board's USB OTG port (CN7) presents a USB gadget with `usb0` at 192.168.7.2 on the A7 Linux side, but macOS doesn't create a corresponding network interface. This blocks SCP/SSH file deployment to the board, which is the primary development workflow for A7 Linux apps.

**Root cause:** The Buildroot kernel is likely presenting an RNDIS gadget (or composite RNDIS+ECM). macOS has zero native RNDIS support, and the old HoRNDIS driver is dead on modern macOS (Big Sur+). Even composite devices with ECM as a secondary configuration fail because macOS no longer falls through to configuration 2.

**Current state:**
- `usb0` exists on the board at 192.168.7.2
- macOS sees `STM32MP1@02100000` USB device (VID 0x1d6b, class 0xEF composite)
- No `enX` interface on macOS gets an IP or even becomes "active"

## Approach

Rebuild the Buildroot kernel with a **pure CDC-ECM gadget** (no RNDIS) and verify macOS creates a network interface. Two sub-tasks:

1. **Kernel config change**: Disable RNDIS in the USB gadget stack
2. **Init script**: Ensure `g_ether` loads at boot with correct CDC-ECM configuration
3. **macOS-side**: Manual IP assignment to the new `enX` interface

### Alternative: Wired Ethernet
The DK2 has a 10/100 Ethernet jack. If the board is near a router/switch, this sidesteps the USB gadget issue entirely. Worth keeping as a fallback, but USB gadget is more convenient for portable dev.

## Solution

### Step 1: Identify current gadget configuration

From the A7 serial console:
```sh
# Check what gadget module is loaded
lsmod | grep -i usb
cat /sys/kernel/config/usb_gadget/*/UDC  # if configfs
ls /sys/class/udc/
```

### Step 2: Rebuild kernel with CDC-ECM only

In Buildroot:
```
CONFIG_USB_GADGET=y
CONFIG_USB_DWC2=y
CONFIG_USB_ETH=m           # g_ether module
CONFIG_USB_ETH_RNDIS=n     # CRITICAL: disable RNDIS
```

Or if using configfs (more modern):
```sh
modprobe libcomposite
# Create pure ECM gadget (not composite with RNDIS)
mkdir -p /sys/kernel/config/usb_gadget/g1
echo 0x1d6b > /sys/kernel/config/usb_gadget/g1/idVendor
echo 0x0104 > /sys/kernel/config/usb_gadget/g1/idProduct
mkdir -p /sys/kernel/config/usb_gadget/g1/functions/ecm.usb0
mkdir -p /sys/kernel/config/usb_gadget/g1/configs/c.1
ln -s /sys/kernel/config/usb_gadget/g1/functions/ecm.usb0 /sys/kernel/config/usb_gadget/g1/configs/c.1/
echo "49000000.usb-otg" > /sys/kernel/config/usb_gadget/g1/UDC
ifconfig usb0 192.168.7.2 netmask 255.255.255.0 up
```

### Step 3: Rebuild and flash SD card

```sh
# In Docker container
linux-build.run_command(container, "make linux-rebuild && make")
linux-build.collect_artifacts(container, host_path="/tmp/stm32mp1-sdcard")
# Flash sdcard.img to SD card
```

### Step 4: Verify on macOS

After board boots with new kernel:
1. Check `ifconfig -a` for new `enX` interface
2. Assign IP: `sudo ifconfig enX 192.168.7.1 netmask 255.255.255.0 up`
3. Test: `ping 192.168.7.2`
4. SSH: `ssh root@192.168.7.2`

### macOS NetworkConnection notification caveat

Recent macOS versions (Sonoma/Sequoia) require the gadget to send a CDC ECM NetworkConnection management element notification ("link is up"). The Linux `f_ecm.c` driver does send this, so it should work. If it doesn't:
- Check `dmesg` on macOS for USB errors
- Try `IORegistryExplorer` to see if the CDC-ECM interface is enumerated
- Worst case: use wired Ethernet as fallback

## Verification

- [ ] `lsmod` on board shows `g_ether` or `usb_f_ecm` (not `usb_f_rndis`)
- [ ] macOS `ifconfig -a` shows a new `enX` interface when board is connected
- [ ] `ping 192.168.7.2` from Mac succeeds
- [ ] `ssh root@192.168.7.2` works
- [ ] `linux-build.deploy()` successfully SCPs files to the board
