# Kernel Drivers — DWC3 Core, Platform Glue, PHY Driver

## Summary

Linux USB support for the Alif E7 uses a two-layer driver stack: the `dwc3-ensemble.c` platform glue driver (handles clocks, power, regulators) and the standard DWC3 core driver (handles USB protocol). There is no separate PHY driver — PHY power and reset are done via raw register writes in the glue driver. Zephyr uses a different UDC driver (`udc_dwc3.c`) with Alif-specific DMA address translation.

## Key Facts

- **Glue driver**: `dwc3-ensemble.c`, compatible `"alif,ensemble-usb3"` [S02]
- **Core driver**: Standard `drivers/usb/dwc3/core.c`, compatible `"snps,dwc3"` [S02]
- **No PHY driver** — raw `ioremap()` to fixed addresses in glue driver [S02]
- **Zephyr UDC driver**: `udc_dwc3.c` with `CONFIG_UDC_DWC3_ALIF` for address translation [S07]
- **USB disabled by default** in defconfig: `# CONFIG_USB_SUPPORT is not set` [S04, S06]

## Driver Stack

```
┌─────────────────────────┐
│  USB Gadget (g_serial)  │  CONFIG_USB_G_SERIAL
├─────────────────────────┤
│  USB Gadget Framework   │  CONFIG_USB_GADGET
├─────────────────────────┤
│  DWC3 Core Driver       │  CONFIG_USB_DWC3 (drivers/usb/dwc3/core.c)
├─────────────────────────┤
│  DWC3 Ensemble Glue     │  CONFIG_USB_DWC3_ENSEMBLE (drivers/usb/dwc3/dwc3-ensemble.c)
├─────────────────────────┤
│  No PHY Driver          │  PHY power via raw ioremap() in glue
└─────────────────────────┘
```

## Platform Glue: dwc3-ensemble.c

### Probe Sequence

```c
static int dwc3_ensemble_probe(struct platform_device *pdev) {
    // 1. Get and enable clocks
    clk_get("usb_clk");  clk_get("dwc_clk");
    clk_prepare_enable(usb_clk);  clk_prepare_enable(dwc_clk);

    // 2. Power up USB PHY
    power_control();
    // Writes: ioremap(0x1A609008) -> clear bits 16,17
    //         ioremap(0x4903F0AC) -> clear bit 8

    // 3. Get and enable regulators
    devm_regulator_get(dev, "vdd33");  regulator_enable(vdd33);
    devm_regulator_get(dev, "vdd18");  regulator_enable(vdd18);

    // 4. Populate child DWC3 node
    of_platform_populate(np, NULL, NULL, dev);
}
```

### Power Control Registers

```c
#define USB_CTRL2_PHY_POR_REG       0x4903F0AC
#define PWR_CTRL_REG                0x1A609008
#define PWR_CTRL_UPHY_PWR_MASK      (1U << 16)   // CLEAR to enable power
#define PWR_CTRL_UPHY_ISO           (1U << 17)   // CLEAR to disable isolation
#define USB_CTRL2_PHY_POR           (1U << 8)    // CLEAR to release PHY POR
```

### Kconfig

```kconfig
config USB_DWC3_ENSEMBLE
    tristate "ALIF ENSEMBLE Platform"
    depends on (ARM) && OF
    default USB_DWC3
```

### Known Issues

1. **Raw ioremap**: Uses `ioremap()` to fixed physical addresses instead of proper power domain or PHY framework. Not upstreamable. [S06]
2. **Regulator mismatch**: Calls `devm_regulator_get()` for vdd33/vdd18 but DT doesn't provide supply properties. Gets dummy regulators. [S04, S06]
3. **PHY init also in pinctrl**: `pinctrl-devkit.c` writes the same three PHY power registers (CGU 0x1A602014, PMU 0x1A609008, EXPSLV 0x4903F0AC). Both the glue driver and pinctrl do PHY init — double-init is safe (idempotent). [S13]
4. **All USB built-in, not modules**: The defconfig builds everything as `=y`. No `kernel-module-dwc3` or `kernel-module-usb-f-fs` packages exist. Yocto RDEPENDS must NOT reference these for E7 — use machine overrides. [S13]

## DWC3 Core Driver

The standard mainline DWC3 core driver handles USB protocol. Key init steps:

1. Read GSNPSID — verify `0x5533xxxx`
2. Core soft reset (GCTL.CORESOFTRESET = 1, wait, clear)
3. PHY soft reset (GUSB2PHYCFG0.PHYSOFTRST = 1, 50ms, clear, 50ms)
4. Read GCTL, set PRTCAPDIR based on `dr_mode`:
   - `"peripheral"` → PRTCAPDIR = 2
   - `"host"` → PRTCAPDIR = 1
   - `"otg"` → PRTCAPDIR = 3
5. Apply DT quirks: burst adjustment, frame length, LPM disable, suspend PHY disable
6. Set up event buffer (GEVNTADR0, GEVNTSIZ0)
7. Register as UDC (gadget) or HCD (host)

## Zephyr DWC3 UDC Driver

`drivers/usb/udc/udc_dwc3.c` in zephyr_alif: [S07]

### Alif-Specific Code (CONFIG_UDC_DWC3_ALIF)

DMA address translation for M55 TCM:
```c
#if CONFIG_UDC_DWC3_ALIF
trb_ptr->buf_ptr_low = LOWER_32_BITS(local_to_global((void *)(params.param1)));
drv->regs->GEVNTADRLO0 = local_to_global((void *)LOWER_32_BITS(event_buf->buf));
#endif
```

### PHY Reset (identical timing to bare-metal)

```c
static void udc_dwc3_reset_phy_and_core(udc_dwc3_driver_t *drv) {
    SET_BIT(drv->regs->GCTL, USB_GCTL_CORESOFTRESET);      // Assert core reset
    SET_BIT(drv->regs->GUSB2PHYCFG0, USB_GUSB2PHYCFG_PHYSOFTRST);  // Assert PHY reset
    k_busy_wait(50000);  // 50ms
    CLEAR_BIT(drv->regs->GUSB2PHYCFG0, USB_GUSB2PHYCFG_PHYSOFTRST);
    k_busy_wait(50000);  // 50ms
    CLEAR_BIT(drv->regs->GCTL, USB_GCTL_CORESOFTRESET);
}
```

### Zephyr Kconfig

```kconfig
UDC_DWC3              # Core driver (auto-enabled by DT)
UDC_DWC3_DMA          # DMA support (default y)
UDC_DWC3_ALIF         # Alif address translation
UDC_DWC3_STACK_SIZE   # Thread stack (default 512)
UDC_DWC3_THREAD_PRIORITY  # Thread priority (default 8)
UDC_DWC3_MAX_QMESSAGES   # Event queue depth (4-64, default 8)
```

## Kconfig Options (Linux)

### Required for Gadget Mode (usb.cfg fragment)

```
CONFIG_USB_SUPPORT=y
CONFIG_USB_COMMON=y
CONFIG_USB_ARCH_HAS_HCD=y
CONFIG_USB_DWC3=y
CONFIG_USB_DWC3_GADGET=y
CONFIG_USB_DWC3_OF_SIMPLE=y
CONFIG_USB_DWC3_ENSEMBLE=y
CONFIG_USB_GADGET=y
CONFIG_USB_LIBCOMPOSITE=y
CONFIG_USB_F_ACM=y
CONFIG_USB_U_SERIAL=y
CONFIG_USB_F_SERIAL=y
CONFIG_USB_G_SERIAL=y
```

### Required for Host Mode (usb_host.cfg fragment)

```
CONFIG_USB=y
CONFIG_USB_SUPPORT=y
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_XHCI_PLATFORM=y
CONFIG_USB_DWC3=y
CONFIG_USB_DWC3_HOST=y
CONFIG_USB_DWC3_OF_SIMPLE=y
CONFIG_USB_DWC3_ENSEMBLE=y
CONFIG_USB_STORAGE=y
CONFIG_USB_ACM=y
CONFIG_SCSI=y
CONFIG_BLK_DEV_SD=y
```

### Conflict Warning

`CONFIG_USB_DWC3_GADGET` and `CONFIG_USB_DWC3_HOST` are **mutually exclusive**. Setting both in the same kernel build (e.g., enabling both `apss-usb` and `apss-usb-host` DISTRO_FEATURES) will cause a build error or undefined behavior. Use `CONFIG_USB_DWC3_DUAL_ROLE` for both modes. [S04]

## Module Parameters

The DWC3 core driver accepts module parameters including:
- `maximum_speed`: Override max USB speed
- No Alif-specific module parameters identified

## Key Source Files

### Linux

| File | Purpose |
|---|---|
| `drivers/usb/dwc3/dwc3-ensemble.c` | Alif platform glue driver |
| `drivers/usb/dwc3/core.c` | DWC3 core driver |
| `drivers/usb/dwc3/gadget.c` | DWC3 gadget mode |
| `drivers/usb/dwc3/host.c` | DWC3 host mode (xHCI) |
| `drivers/clk/alif/clk-ensemble.c` | Clock driver (USB clock defs) |

### Zephyr

| File | Purpose |
|---|---|
| `drivers/usb/udc/udc_dwc3.c` | DWC3 UDC driver |
| `drivers/usb/udc/udc_dwc3.h` | TRB/driver structures |
| `soc/alif/ensemble/common/soc_common.c` | SoC USB PHY init |
| `drivers/clock_control/clock_control_alif_ensemble.c` | Clock enable |
| `drivers/power_domain/power_domain_alif.c` | Power domain via SE |

### Bare-metal

| File | Purpose |
|---|---|
| `tinyusb/src/portable/alif/alif_e7_dk/dcd_ensemble.c` | TinyUSB device controller |
| `tinyusb/src/portable/alif/alif_e7_dk/dcd_ensemble_def.h` | Register definitions (868 lines) |
| `alif_ensemble-cmsis-dfp/drivers/source/usb/usbd_initialize.c` | CMSIS USB init |

## Open Questions

- ~~Does Alif use dwc3-of-simple or a custom glue driver?~~ Resolved: Custom `dwc3-ensemble.c` [S02]
- ~~Is there an Alif USB PHY driver?~~ Resolved: No — raw register writes in glue [S02]
- ~~What Kconfig options are needed?~~ Resolved: See fragments above [S04, S11]
- Should the glue driver be refactored to use the generic PHY framework?
- Should power control use a proper power domain driver instead of ioremap?

## Source References

[S02] linux_alif, [S04] meta-alif-ensemble, [S06] build-setup, [S07] sdk-alif/zephyr_alif, [S08] TinyUSB, [S11] Getting Started Guide — See [sources.md](sources.md)
