# Boot Sequence — TF-A PHY Init, Pre-Linux Requirements

## Summary

USB PHY initialization on the Alif E7 happens at different stages depending on the software stack. For Linux, TF-A (BL32/SP_MIN) performs USB PHY power-up before the kernel boots. For Zephyr, SoC init code runs at PRE_KERNEL_1. For bare-metal (TinyUSB/CMSIS), the application handles all init directly. This document traces each path.

## Key Facts

- TF-A calls `service_enable_usb_phy()` during BL32 platform setup — before Linux boots [S01]
- No runtime SMC/PSCI call for USB — the TF-A init is one-shot [S01]
- Linux `dwc3-ensemble.c` also writes VBAT/CLKCTL registers — double-init is safe (idempotent) [S02]
- Zephyr does PHY power in SoC init at `PRE_KERNEL_1` priority [S07]
- Bare-metal (TinyUSB) does everything in `dcd_init()` — no firmware dependency [S08]

## Linux Boot Path (TF-A + Kernel)

### Phase 1: TF-A (BL32 / SP_MIN)

TF-A runs on the A32 in AArch32 secure mode (SP_MIN, not ATF BL31): [S01]

1. **Platform setup** calls `service_enable_usb_phy()`
2. **SE service 310** (GET_RUN_CFG): Read current `run_profile_t` via MHU
3. **Modify profile**: Set `phy_pwr_gating |= (1 << 1)` (USB_PHY bit)
4. **SE service 311** (SET_RUN_CFG): Write modified profile via MHU
5. **Direct register writes**:
   - `PWR_CTRL (0x1A609008)`: Clear bits 16,17 — enable PHY power, disable isolation
   - `USB_CTRL2 (0x4903F0AC)`: Clear bit 8 — release PHY POR

After this, TF-A hands off to Linux (NS world). The PHY is powered but the DWC3 controller is not initialized.

### Phase 2: Linux Kernel (dwc3-ensemble probe)

The `dwc3-ensemble.c` glue driver probe sequence: [S02, S06]

1. **Get clocks**: `usb_clk` and `dwc_clk` from device tree clock provider
2. **Enable clocks**: `clk_prepare_enable()` for both clocks
3. **Power control**: `power_control()` does the same VBAT/CLKCTL register writes as TF-A
   - Clear `PWR_CTRL[16:17]` — safe to repeat (idempotent)
   - Clear `USB_CTRL2[8]` — safe to repeat
4. **Get regulators**: `devm_regulator_get(dev, "vdd33")` and `"vdd18"` (currently returns dummy — see Known Issues)
5. **Populate children**: `of_platform_populate()` instantiates the child `snps,dwc3` node
6. **DWC3 core probe**: Standard DWC3 driver takes over, reads GSNPSID, configures GCTL, etc.

### Phase 3: DWC3 Core Init (within kernel)

The standard DWC3 core driver (`drivers/usb/dwc3/core.c`) runs: [S10]
1. Read GSNPSID — verify controller ID
2. Core soft reset (GCTL.CORESOFTRESET)
3. PHY soft reset (GUSB2PHYCFG0.PHYSOFTRST)
4. Configure GCTL.PRTCAPDIR based on `dr_mode` DT property
5. Set up event buffers (GEVNTADR0, GEVNTSIZ0, GEVNTCOUNT0)
6. Register UDC (gadget mode) or HCD (host mode)

## Zephyr Boot Path

Zephyr's init is more structured but simpler: [S07]

### SoC Init (PRE_KERNEL_1)

`soc_common.c` runs unconditionally if USB node is status="okay":
```c
#if DT_NODE_HAS_STATUS(DT_NODELABEL(usb), okay)
    sys_clear_bits(VBAT_PWR_CTRL, BIT(16) | BIT(17));  // PHY power + isolation
    sys_clear_bits(EXPMST_USB_CTRL2, BIT(8));           // PHY POR
#endif
```

### Clock Enable (driver init)

Clock control driver enables USB clock via:
1. CGU_CLK_ENA[22] — 20MHz USB ref clock
2. PERIPH_CLK_ENA[20] — USB peripheral clock gate

### DWC3 UDC Driver Init

`udc_dwc3.c` then runs: [S07]
1. PHY and core soft reset (50ms delays each)
2. Configure UTMI PHY interface (8 or 16-bit)
3. Set device mode (GCTL.PRTCAPDIR = 2)
4. Set up event buffer (with `local_to_global()` for DMA addresses)

## Bare-Metal Boot Path (TinyUSB / CMSIS)

No firmware dependency — everything in one function: [S08]

1. Enable CGU_CLK_ENA[22] + PERIPH_CLK_ENA[20]
2. Clear VBAT_PWR_CTRL[16:17] + USB_CTRL2[8]
3. Verify GSNPSID = 0x5533330B
4. Device controller soft reset (DCTL.CSFTRST)
5. Optional: full PHY reset (GCTL.CORESOFTRESET + GUSB2PHYCFG0.PHYSOFTRST, 50ms each)
6. Configure bus (GSBUSCFG0), PHY (GUSB2PHYCFG0), GCTL, GFLADJ
7. Set up event buffer in bulk SRAM
8. Configure device speed, enable events, set up EP0
9. Set DCTL.RUN_STOP = 1 to start enumeration

## Boot Flow Timeline

```
Power-On
  │
  ├─ [TF-A path]
  │   BL1 → BL2 → BL32 (SP_MIN)
  │     └─ service_enable_usb_phy()
  │         ├─ SE service 310/311 (AIPM profile)
  │         └─ VBAT + CLKCTL register writes
  │   BL33 (Linux kernel)
  │     └─ dwc3-ensemble probe
  │         ├─ clk_prepare_enable(usb_clk, dwc_clk)
  │         ├─ power_control() [redundant but safe]
  │         └─ of_platform_populate() → DWC3 core probe
  │
  ├─ [Zephyr path]
  │   SoC init (PRE_KERNEL_1)
  │     └─ VBAT + CLKCTL register writes
  │   Clock driver init
  │     └─ CGU + PERIPH clock enable
  │   DWC3 UDC driver init
  │     └─ PHY reset → configure → event buffer
  │
  └─ [Bare-metal path]
      Application dcd_init()
        └─ Clock → Power → Verify ID → Reset → Configure → Start
```

## What State Must Exist Before Linux Probe

For the Linux DWC3 driver to probe successfully: [S01, S02]

1. **PD_SYST must be powered** — the USB module is in PD6
2. **USB PHY must be powered** — AIPM phy_pwr_gating bit 1 set
3. **VBAT isolation must be cleared** — PWR_CTRL bits 16,17 cleared
4. **PHY POR must be released** — USB_CTRL2 bit 8 cleared
5. **Clocks must be available** — PLL3 must be running for usb_clk derivation

Items 2-4 are handled by TF-A's `service_enable_usb_phy()`. Item 1 is handled by TF-A power domain setup. Item 5 is handled by TF-A clock initialization.

**If TF-A skips USB init**, the Linux driver will still attempt the VBAT/CLKCTL writes in its own `power_control()`, but the AIPM profile bits may not be set, potentially leaving the PHY unpowered at the SE level.

## Open Questions

- ~~Does TF-A fully initialize the PHY or just power it?~~ Resolved: Just powers it + releases POR. DWC3 init is left to Linux. [S01]
- ~~Is there a runtime PSCI call for USB PHY power control?~~ Resolved: No. [S01]
- ~~What happens if TF-A skips USB init — can Linux recover?~~ Partially resolved: Linux repeats the VBAT/CLKCTL writes but may not set AIPM bits. [S01, S02]
- Are there timing constraints between PHY power-up and DWC3 soft reset?
- What's the minimum delay after clearing PHY_POR before accessing DWC3 registers?

## Source References

[S01] TF-A, [S02] linux_alif, [S07] sdk-alif/zephyr_alif, [S08] TinyUSB/CMSIS-DFP, [S10] HWRM v2.8 — See [sources.md](sources.md)
