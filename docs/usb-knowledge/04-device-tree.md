# Device Tree — DWC3 Bindings, PHY Node, Interrupts

## Summary

The Alif E7 USB subsystem uses a two-level device tree structure: an outer wrapper node (`alif,ensemble-usb3`) for the platform glue driver, containing a child node (`snps,dwc3`) for the standard DWC3 core driver. Both nodes are disabled by default and enabled at build time through the Yocto DCT mechanism. There is no separate PHY node — the on-chip UTMI+ PHY is initialized inline by the glue driver.

## Key Facts

- **Wrapper compatible**: `"alif,ensemble-usb3"` (dwc3-ensemble.c glue driver) [S02]
- **Core compatible**: `"snps","snps,dwc3"` (standard DWC3 core driver) [S02]
- **Base address**: `0x48200000`, size `0x100000` (1MB) [S02]
- **Interrupt**: GIC SPI 26, level-high [S02]
- **dr_mode**: `"peripheral"` — hardcoded in DTSI, never overridden for host mode [S02, S04]
- **No PHY node** — PHY is referenced via clock phandle as a workaround [S02]
- **Status**: Both nodes disabled by default; enabled via DCT at build time [S04, S06]

## Linux Device Tree (v6.12-dev branch)

### Full DT Snippet

```dts
hsusb: dwc3@48200000 {
    compatible = "alif,ensemble-usb3";
    #address-cells = <1>;
    #size-cells = <1>;
    ranges = <0x48200000 0x48200000 0x100000>;
    clock-names = "usb_clk", "dwc_clk";
    clocks = <&psclks ENSEMBLE_USB_CLK>,
             <&psclks ENSEMBLE_DWC_USB_CLK>;
    status = "disabled";

    dwc3: usb@48200000 {
        compatible = "snps","snps,dwc3";
        reg = <0x48200000 0x100000>;
        interrupts = <GIC_SPI 26 IRQ_TYPE_LEVEL_HIGH>;
        phy = <&psclks ENSEMBLE_USB_CLK>;
        phy-names = "usb2_phy";
        dr_mode = "peripheral";
        snps,hsphy_interface = "utmi";
        phy_type = "utmi_wide";
        maximum-speed = "high-speed";
        snps,dis_u3_susphy_quirk;
        snps,dis_u2_susphy_quirk;
        snps,incr-burst-type-adjustment = <1>, <4>, <8>, <16>;
        snps,quirk-frame-length-adjustment = <0x20>;
        snps,usb2-lpm-disable;
        status = "disabled";
    };
};
```

### Board DTS Override (devkit-e8.dts)

```dts
&hsusb {
    status = HSUSB_STATUS;
    dwc3: usb@48200000 {
        status = HSUSB_STATUS;
    };
};
```

`HSUSB_STATUS` is defined as `"disabled"` in `devkit_ex_dct_defines.h` and rewritten to `"okay"` by `dct-kernel.bbclass` when any of `apss-usb`, `apss-usb-host`, or `apss-usb-boot` is in DISTRO_FEATURES. [S04, S06]

### Fixed Regulators (defined but NOT wired to USB)

```dts
reg_3p3v: regulator-3v3 {
    compatible = "regulator-fixed";
    regulator-min-microvolt = <3300000>;
    regulator-max-microvolt = <3300000>;
};
reg_1p8v: regulator-1v8 {
    compatible = "regulator-fixed";
    regulator-min-microvolt = <1800000>;
    regulator-max-microvolt = <1800000>;
};
```

**Known Issue**: The glue driver calls `devm_regulator_get(dev, "vdd33")` and `devm_regulator_get(dev, "vdd18")`, but neither `vdd33-supply` nor `vdd18-supply` properties exist on the hsusb node. The driver gets dummy regulators (or fails, depending on kernel config). [S04, S06]

## Zephyr Device Tree

### USB Node (ensemble/common/e1.dtsi)

```dts
usb: usb@48200000 {
    compatible = "snps,dwc3";
    reg = <0x48200000 0xca04>;
    clocks = <&clockctrl ALIF_USB_CLK>;
    maximum-speed = "high-speed";
    interrupts = <101 3>;
    num-out-eps = <4>;
    num-in-eps = <4>;
    status = "disabled";
};
```

Key differences from Linux DT: [S07]
- **No wrapper node** — Zephyr uses `"snps,dwc3"` directly
- **Register size**: `0xCA04` (precise) vs `0x100000` (full 1MB region in Linux)
- **IRQ**: 101 (NVIC number) vs GIC SPI 26 (different interrupt controller)
- **Endpoint count**: Explicit `num-out-eps`/`num-in-eps` = 4 each
- **No PHY properties** — Zephyr handles PHY in SoC init code

### DWC3 Binding (snps,dwc3.yaml)

Required properties: `reg`, `interrupts`, `clocks`, `num-in-eps`, `num-out-eps`
Inherits `usb-controller.yaml` for `maximum-speed`.

## DT Node Naming History

The v6.12-dev branch cleaned up node names: [S03]

| Property | APSS-v2.1.0 | v6.12-dev |
|---|---|---|
| Wrapper label | `hsusb: dwc3-drd` | `hsusb: dwc3@48200000` |
| Child label | `usbdual_hs: usb-dual@48200000` | `dwc3: usb@48200000` |

No functional change — cosmetic only.

## Property Reference

### Wrapper Node (alif,ensemble-usb3)

| Property | Value | Purpose |
|---|---|---|
| `compatible` | `"alif,ensemble-usb3"` | Matches dwc3-ensemble.c |
| `clock-names` | `"usb_clk"`, `"dwc_clk"` | USB ref clock, DWC bus clock |
| `clocks` | phandles to clock provider | Clock references |
| `#address-cells` | `<1>` | Child address translation |
| `#size-cells` | `<1>` | Child size specification |
| `ranges` | `<0x48200000 0x48200000 0x100000>` | Pass-through address mapping |

### Child Node (snps,dwc3)

| Property | Value | Purpose |
|---|---|---|
| `compatible` | `"snps","snps,dwc3"` | Matches DWC3 core driver |
| `reg` | `<0x48200000 0x100000>` | Register range |
| `interrupts` | `<GIC_SPI 26 IRQ_TYPE_LEVEL_HIGH>` | USB interrupt |
| `dr_mode` | `"peripheral"` | Device mode (not host, not OTG) |
| `maximum-speed` | `"high-speed"` | USB 2.0 HS (480 Mbps) |
| `snps,hsphy_interface` | `"utmi"` | PHY interface type |
| `phy_type` | `"utmi_wide"` | PHY data width |
| `snps,dis_u3_susphy_quirk` | (boolean) | Disable U3 suspend PHY |
| `snps,dis_u2_susphy_quirk` | (boolean) | Disable U2 suspend PHY |
| `snps,incr-burst-type-adjustment` | `<1>, <4>, <8>, <16>` | AXI burst configuration |
| `snps,quirk-frame-length-adjustment` | `<0x20>` | Frame length adj (GFLADJ) |
| `snps,usb2-lpm-disable` | (boolean) | Disable USB 2.0 LPM |

## DTS File Selection (Critical)

There are 4 DTS files for the E7. Using the wrong one causes clock misconfiguration and UART baud rate corruption: [S13]

| File | compatible | Correct? |
|---|---|---|
| `appkit-e7.dts` | `"arm,Appkit-E7"` | NO — all clocks 20MHz |
| `appkit-e7-devboard.dts` | `"arm,Appkit-E7"` | NO — all clocks 20MHz |
| **`appkit-e7-flatboard.dts`** | **`"alif,ensemble"`** | **YES (AppKit)** |
| `devkit-e7.dts` | `"alif,ensemble"` | YES (DevKit) |

## HSUSB_STATUS: DevKit vs AppKit

The `HSUSB_STATUS` macro differs per board: [S13]
- `devkit_ex_dct_defines.h` → `"disabled"` (USB off by default)
- `appkit_ex_dct_defines.h` → `"okay"` (USB on by default)

Building with the wrong board header silently disables USB with no build warning.

## Known Issues

1. **dr_mode hardcoded**: `"peripheral"` in DTSI with no board-level override. Host mode kernel configs enable XHCI but the DWC3 core still initializes as peripheral. Need DT overlay or DTSI change for host mode. [S04, S06]

2. **Missing regulator supplies**: `vdd33-supply` and `vdd18-supply` not wired to hsusb node despite driver expecting them. Fixed regulators exist but aren't connected. [S04, S06]

3. **PHY reference hack**: `phy = <&psclks ENSEMBLE_USB_CLK>` references a clock as a PHY — this is a workaround, not a proper PHY binding. The PHY lookup fails silently; PHY init happens in `pinctrl-devkit.c` (not the DWC3 driver). [S02, S13]

## Open Questions

- ~~What compatible string does Alif use?~~ Resolved: `"alif,ensemble-usb3"` (wrapper) + `"snps,dwc3"` (core) [S02]
- ~~Is there a glue/wrapper layer in the DT?~~ Resolved: Yes, the hsusb wrapper node [S02]
- ~~How is the PHY referenced?~~ Resolved: Clock phandle hack, no real PHY node [S02]
- ~~What interrupts are routed?~~ Resolved: GIC SPI 26 [S02]
- Should the PHY reference be replaced with a proper generic-phy binding?
- How should dr_mode be changed for host mode — DT overlay or DTSI modification?

## Source References

[S02] linux_alif APSS-v2.1.0, [S03] linux_alif v6.12-dev, [S04] meta-alif-ensemble, [S06] build-setup, [S07] sdk-alif/zephyr_alif, [S11] Getting Started Guide — See [sources.md](sources.md)
