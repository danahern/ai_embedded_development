# Troubleshooting — Known Issues, Debug Techniques

## Summary

USB bring-up on the Alif E7 commonly fails at PHY power sequencing, clock configuration, device tree errors, or driver probe issues. This document collects confirmed failure modes, known bugs in the current Alif software stack, and diagnostic techniques.

## Known Issues

### 1. dr_mode Hardcoded to "peripheral"

**Severity**: High — blocks host mode operation
**Source**: [S04, S06]

The device tree DTSI sets `dr_mode = "peripheral"` with no board-level override. Even when the `usb_host.cfg` kernel fragment is applied (CONFIG_USB_DWC3_HOST=y), the DWC3 core driver reads dr_mode from DT and initializes as peripheral. Host mode requires a DT overlay or DTSI modification:

```dts
&dwc3 {
    dr_mode = "host";
};
```

### 2. Missing Regulator Supply Properties

**Severity**: Medium — may cause probe failure depending on kernel config
**Source**: [S04, S06]

The `dwc3-ensemble.c` driver calls `devm_regulator_get(dev, "vdd33")` and `devm_regulator_get(dev, "vdd18")`, but the device tree hsusb node has no `vdd33-supply` or `vdd18-supply` properties. The fixed regulators `reg_3p3v` and `reg_1p8v` exist in the board DTS but aren't connected.

**Fix**: Add supply properties to the hsusb node:
```dts
&hsusb {
    vdd33-supply = <&reg_3p3v>;
    vdd18-supply = <&reg_1p8v>;
};
```

Or make the regulator calls optional in the driver (use `devm_regulator_get_optional()`).

### 3. Gadget + Host Config Fragment Conflict

**Severity**: High — build failure or undefined behavior
**Source**: [S04]

Setting both `apss-usb` and `apss-usb-host` in DISTRO_FEATURES applies both `usb.cfg` (CONFIG_USB_DWC3_GADGET=y) and `usb_host.cfg` (CONFIG_USB_DWC3_HOST=y). These are mutually exclusive Kconfig options.

**Fix**: Use CONFIG_USB_DWC3_DUAL_ROLE=y instead, or ensure only one USB DISTRO_FEATURE is set.

### 4. PHY Power Bit Polarity

**Severity**: Critical if misunderstood
**Source**: [S08]

The VBAT power control bits have **inverted polarity**:
- UPHY_PWR_MASK (bit 16): **CLEAR** to enable power, SET to disable
- UPHY_ISO (bit 17): **CLEAR** to disable isolation, SET to enable

Setting these bits (instead of clearing them) will power-gate the USB PHY.

### 5. No Runtime USB Power Control

**Severity**: Low — design limitation
**Source**: [S01]

TF-A's `service_enable_usb_phy()` runs once at boot. There is no SMC/PSCI call to toggle USB PHY power at runtime. If USB PHY power needs to be toggled (e.g., for suspend/resume), it must be done through direct register writes from the Linux driver.

### 6. DMA Buffer Placement (Bare-metal / Zephyr)

**Severity**: Critical for non-Linux stacks
**Source**: [S08]

USB DMA buffers (event buffer, TRBs, data buffers) must be in **bulk SRAM** (0x02000000 or 0x08000000), NOT in TCM. The DWC3 DMA controller uses global bus addresses. TCM addresses are core-local and invisible to the DMA engine.

Symptoms: `buserraddrvld` bit set in GSTS register, no USB events received.

### 7. PHY Reference Hack in Device Tree

**Severity**: Low — functional but incorrect
**Source**: [S02]

The DT uses `phy = <&psclks ENSEMBLE_USB_CLK>` which references a clock provider as a PHY. This is a workaround — the DWC3 binding expects a proper PHY phandle. Works because the DWC3 core driver has fallback paths when PHY lookup fails.

### 8. SE AIPM Service ID Off-By-One

**Severity**: Critical — crashes the SE and hangs the A32 core
**Source**: [S13: Conversation history]

The local `services_lib_ids.h` in some TF-A branches has wrong enum values. The upstream Alif CMSIS DFP starts `SERVICE_POWER_STOP_MODE_REQ_ID` at 300, but local copies may start at 301, shifting every subsequent ID by +1:
- Local GET_RUN = 311, **correct = 310**
- Local SET_RUN = 312, **correct = 311**

Sending the wrong ID (e.g., 311 intending GET) causes the SE to interpret it as SET_RUN with a zeroed payload. The SE crashes during processing, and the A32 core hangs after `mhu_secure_message_send()` completes successfully.

Additionally, local structs may have 4 extra fields (`wakeup_events`, `ewic_cfg`, `vtor_address`, `vtor_address_ns`) not present upstream, making the struct 16 bytes too large.

**Fix**: Always cross-reference service ID enums against the upstream CMSIS DFP pack, not local copies.

### 9. HSUSB_STATUS DevKit vs AppKit DTS Mismatch

**Severity**: High — silently disables USB
**Source**: [S13: Conversation history]

The DTS uses `#define HSUSB_STATUS` from board-specific header files:
- `devkit_ex_dct_defines.h` → `HSUSB_STATUS "disabled"`
- `appkit_ex_dct_defines.h` → `HSUSB_STATUS "okay"`

Building for the wrong board (or using the wrong DTS header) silently disables USB in the device tree. There is no build-time warning.

### 10. DWC3 "Failed to get clk 'ref': -2" is Non-Fatal

**Severity**: None — cosmetic warning only
**Source**: [S13: Conversation history]

The error `dwc3 48200000.usb-dual: Failed to get clk 'ref': -2` appears on every boot. The DWC3 core (`core.c` lines 1449-1457) checks if the error is `-EPROBE_DEFER`; if not, it sets `dwc->num_clks = 0` and **continues**. The DTS has `phy = <&usbclk>` pointing to a fixed-clock, but no `clocks`/`clock-names` on the inner `snps,dwc3` node.

**Do not waste time fixing this** — the UDC registers successfully despite it.

### 11. J1 vs J2 USB Port Confusion

**Severity**: High — common time-waster
**Source**: [S13: Conversation history]

Multiple USB ports on the board edge look similar:
- **J1** (micro-USB): **USB Device port** — DWC3 at 0x48200000, used for gadget (ADB/ECM/serial)
- **J2** (USB-C): **PRG_USB** — SE-UART for flashing only, NOT for gadget

PRG_USB is just the FTDI SE-UART. You need a **second** USB cable to J1 for ADB/gadget. Also: charge-only USB cables won't work — must be a data cable.

### 12. OOM on 4MB SRAM with Full USB Stack

**Severity**: High — kernel panic
**Source**: [S13: Conversation history]

The Alif E7 AppKit has only 4MB SRAM. The kernel with DWC3 USB + g_serial + 16 hwsem + SDHCI panics:
```
1024 pages RAM          <- only 4MB total
managed:3512kB          <- 3.5MB usable after kernel
free:200kB              <- almost nothing left
Kernel panic - not syncing: System is deadlocked on memory
```

**USB kernel size impact**: USB DWC3/gadget/FunctionFS adds ~1MB (from ~2.16MB to ~3.16MB).

**Fix**: Either strip kernel config for MRAM-only boot, or use OSPI HyperRAM (32MB at 0xA0000000) via `AP_HYPERRAM_EN=1` in local.conf.

### 13. ConfigFS Mount Timing Race at Boot

**Severity**: Medium — gadget script fails
**Source**: [S13: Conversation history]

ConfigFS writes fail if the filesystem isn't mounted when the gadget init script runs. The script may execute before configfs is available. Fix:
```bash
mount -t configfs none /sys/kernel/config 2>/dev/null
```
Add this at the top of gadget setup scripts, or add a systemd dependency on `sys-kernel-config.mount`.

### 14. Wrong DTS Among Four Options

**Severity**: High — causes baud rate corruption and other failures
**Source**: [S13: Conversation history]

There are 4 DTS files for the E7 in the kernel source. Only one is correct per board:

| File | compatible | Clocks | Correct? |
|---|---|---|---|
| `appkit-e7.dts` | `"arm,Appkit-E7"` | All 20MHz (wrong) | NO |
| `appkit-e7-devboard.dts` | `"arm,Appkit-E7"` | All 20MHz (wrong) | NO |
| **`appkit-e7-flatboard.dts`** | **`"alif,ensemble"`** | **Correct values** | **YES (AppKit)** |
| `devkit-e7.dts` | `"alif,ensemble"` | Correct | YES (DevKit) |

Using the wrong DTS causes UART baud rate corruption (wrong clock divisor calculations).

## Debug Techniques

### Kernel Log Analysis

Check for USB-related messages during boot:
```bash
dmesg | grep -i -E "usb|dwc3|gadget|udc"
```

Expected successful probe log (based on working configs): [S11]
```
dwc3 48200000.usb: DWC3 USB controller
dwc3 48200000.usb: Configuration: peripheral mode
usb 1-1: New USB device found, idVendor=0525, idProduct=a4a7
cdc_acm 1-1:2.0: ttyACM0: USB ACM device
```

### Register Dumps

Key registers to check for USB PHY state:

```bash
# From Linux (requires devmem2 or /dev/mem access):

# Check PHY power state
devmem2 0x1A609008  # VBAT PWR_CTRL
# Bits 16,17 should be 0 (cleared = powered)

# Check PHY POR state
devmem2 0x4903F0AC  # USB_CTRL2
# Bit 8 should be 0 (cleared = reset released)

# Check clock enables
devmem2 0x1A602014  # CGU CLK_ENA
# Bit 22 should be 1 (set = 20MHz clock enabled)

devmem2 0x4903F00C  # PERIPH_CLK_ENA
# Bit 20 should be 1 (set = USB clock gate enabled)

# Check DWC3 controller ID (verify controller is accessible)
devmem2 0x4820C120  # GSNPSID
# Should read 0x5533330B

# Check current mode
devmem2 0x4820C118  # GSTS
# Bits 1:0 = CURMOD (0=Device, 1=Host)

# Check port capability setting
devmem2 0x4820C110  # GCTL
# Bits 13:12 = PRTCAPDIR (1=Host, 2=Device, 3=DRD)
```

### DCTL Register Debugging (Enumeration Failure)

When USB gadget activates but host doesn't see the device, check DCTL:

```bash
devmem 0x4820C704 32   # DCTL — bit 31 = Run/Stop
devmem 0x4820C70C 32   # DSTS — link state, connect speed
devmem 0x4820C140 32   # GHWPARAMS0 — bits 2:0 = mode
```

**DCTL Run/Stop bit 31**:
- 0 = controller stopped, pull-ups not enabled → gadget not bound or PHY issue
- 1 = controller running → if still "not attached", problem is PHY-level (power/clocks)

**GHWPARAMS0 bits 2:0 = 2** means Device-Only mode — **no OTG block**. GOTGCTL reads are meaningless. Don't chase VBUS session valid bits; the DWC3 has no VBUS detection hardware.

You can force Run/Stop on: `devmem 0x4820C704 32 0x80200800`. If the bit sticks (readback confirms bit 31=1) but host still doesn't see the device, the issue is PHY-level — the DWC3 digital logic is running but the USB transceiver isn't driving the bus.

### PHY Init Location (Not Where You'd Expect)

USB PHY initialization is buried in the **pinctrl driver** (`pinctrl-devkit.c`), NOT in the DWC3 glue driver. Three registers must be configured:

| Register | Address | Purpose |
|---|---|---|
| CGU clock | `0x1A602014` | USB 20MHz + 10MHz + HFOSC clocks |
| PMU power (PWR_CTRL) | `0x1A609008` | USB PHY power domain |
| EXPSLV reset | `0x4903F0AC` | USB PHY power-on-reset mask (bit 8) |

Observed values from a running board (all correct but PHY still didn't drive D+):
- `CGU (0x1A602014)` = `0x11E33111` — USB clocks enabled (OK)
- `PMU (0x1A609008)` = `0x00000000` — USB power enabled (OK)
- `EXPSLV (0x4903F0AC)` = `0x00000000` — PHY not in reset (OK)

All three correct but still no enumeration → confirms the SE AIPM power gating is the actual root cause.

### DWC3 Debug Features

The DWC3 core driver has built-in debugfs support:
```bash
# If debugfs is mounted:
ls /sys/kernel/debug/usb/dwc3.0/
# Look for: regdump, mode, link_state, etc.

cat /sys/kernel/debug/usb/dwc3.0/regdump
```

### Device Tree Verification

Verify the DT was correctly modified at build time:
```bash
# Check if USB nodes are enabled
cat /proc/device-tree/dwc3@48200000/status
# Should show "okay"

cat /proc/device-tree/dwc3@48200000/usb@48200000/status
# Should show "okay"

cat /proc/device-tree/dwc3@48200000/usb@48200000/dr_mode
# Shows current dr_mode setting
```

### UDC Status

```bash
# List available UDCs
ls /sys/class/udc/

# Check UDC state
cat /sys/class/udc/*/state
# Should show "configured" when host is connected

# Check current gadget driver
cat /sys/class/udc/*/current_speed
```

### Power Domain Status

```bash
# Check interrupt assignments (USB should have GIC SPI 26)
cat /proc/interrupts | grep -i usb

# Check loaded USB modules
lsmod | grep -i usb
# Or for built-in drivers:
cat /proc/modules | grep dwc3
```

### Common Failure Scenarios

| Symptom | Likely Cause | Check |
|---|---|---|
| No USB device in dmesg | PHY not powered | VBAT PWR_CTRL bits 16,17 |
| "failed to get phy" in dmesg | DT PHY reference issue | DT phy property, can be ignored |
| "failed to get clk 'ref': -2" | Missing clock binding | **Non-fatal** — ignore, UDC works fine |
| "failed to get vdd33" | Missing DT supply property | Add vdd33-supply to DT |
| dwc3 probe fails silently | USB node disabled in DT | Check /proc/device-tree status |
| Host mode doesn't work | dr_mode = "peripheral" | Check DT dr_mode property |
| GSNPSID reads 0x00000000 | Clock not enabled or PHY off | Check all clock/power registers |
| buserraddrvld in GSTS | DMA buffer in wrong memory | Move buffers to bulk SRAM |
| No events after init | Event buffer address wrong | Check GEVNTADR0 is global address |
| UDC shows "not attached" | SE AIPM not ungated USB PHY | Check TF-A has service_enable_usb_phy() |
| DCTL Run/Stop=1 but no enum | PHY not driving D+ | All three power levels + SE AIPM |
| SE hangs after MHU send | Wrong AIPM service ID | Cross-check IDs vs upstream CMSIS DFP |
| Kernel panic "deadlocked on memory" | 4MB SRAM not enough | Strip kernel config or use OSPI HyperRAM |
| USB works on DevKit not AppKit | Wrong HSUSB_STATUS header | Check board-specific dct_defines.h |

## Bare-Metal Init Verification

For TinyUSB or CMSIS, verify init success with this checklist: [S08]

1. GSNPSID reads `0x5533330B` — controller accessible
2. DCTL.CSFTRST auto-clears after assertion — reset works
3. GCTL.PRTCAPDIR = 2 — device mode set
4. GSTS.CURMOD = 0 — confirms device mode
5. DSTS.DEVCTRLHLT = 0 after setting RUN_STOP — controller running
6. Event buffer receives USB Reset event — host connection detected

## Yocto Build Gotchas

### OE Zeus Syntax (NOT Scarthgap)

The Alif BSP uses OE zeus (3.0). All Yocto syntax must use underscore format:

| Scarthgap (wrong) | Zeus (correct) |
|---|---|
| `FILESEXTRAPATHS:prepend` | `FILESEXTRAPATHS_prepend` |
| `RDEPENDS:${PN}` | `RDEPENDS_${PN}` |
| `do_configure:append` | `do_configure_append` |

### cleansstate Required After Removing Fragments

Commenting out a kernel config fragment from SRC_URI does NOT regenerate `.config`. Must run:
```bash
bitbake linux-alif -c cleansstate
```

### BusyBox Compatibility

Init scripts must use `head -n 1` (POSIX), not `head -1` (coreutils-only). BusyBox on the E7 rejects the latter silently.

## Open Questions

- ~~What does a successful Linux probe log look like end-to-end?~~ Partially resolved: see Device Detection logs in [06-gadget-configfs.md]
- Are there known errata for the DWC3 release 3.30b on Alif E7?
- What's the correct procedure for USB suspend/resume without runtime PSCI?
- Does the PHY require any settling time between power-up and first access?

## Source References

[S01] TF-A, [S02] linux_alif, [S04] meta-alif-ensemble, [S06] build-setup, [S07] sdk-alif, [S08] TinyUSB, [S10] HWRM v2.8, [S11] Getting Started Guide, [S13] Conversation history debugging sessions — See [sources.md](sources.md)
