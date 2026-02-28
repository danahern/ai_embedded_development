# Hardware — DWC3 Controller, USB PHY, Clocks, Power Domains

## Summary

The Alif Ensemble E7 integrates a Synopsys DesignWare USB 3.0 (DWC3) controller operating in USB 2.0 High-Speed mode only. It uses an on-chip UTMI+ PHY (no external PHY). USB lives in power domain PD-6 (PD_SYST) and requires coordinated clock and power sequencing across multiple register domains.

## Key Facts

- **Controller**: Synopsys DWC3 (DesignWare USB3), ID `0x5533330B` (release 3.30b) [S08]
- **USB Standard**: USB 2.0 High-Speed (480 Mbps) only, despite "usb3" naming [S02, S10]
- **Base Address**: `0x48200000`, register range 0xCA04 bytes (~51KB) [S07, S08]
- **PHY**: On-chip UTMI+ (supports 8-bit or 16-bit interface width) [S08, S10]
- **Power Domain**: PD_SYST (PD6) — shared with UART, SPI, I2C, Ethernet, SDHC [S07]
- **Endpoints**: 4 IN + 4 OUT (including EP0), up to 16 bidirectional [S07, S11]
- **FIFO**: 1865 x 64-bit entries [S10]
- **Interrupt**: GIC SPI 26 (Linux DT) / NVIC IRQ 101 (Zephyr/bare-metal) [S02, S07, S08]
- **DMA**: Internal DMA controller, requires buffers in bulk SRAM (not TCM) [S08]

## Register Map

### Base Addresses

| Peripheral | Address | Purpose |
|---|---|---|
| USB (DWC3) | `0x48200000` | DWC3 controller base |
| CGU | `0x1A602000` | Clock Generation Unit |
| VBAT | `0x1A609000` | VBAT power domain control |
| CLKCTL_PER_MST | `0x4903F000` | Peripheral master clock/control |

### DWC3 Register Blocks

| Block | Offset | Key Registers |
|---|---|---|
| xHCI CAP | `+0x0000` | CAPLENGTH, HCSPARAMS1-3, HCCPARAMS1-2 |
| Global (GBL) | `+0xC100` | GSBUSCFG0/1, GCTL, GSTS, GSNPSID, GUSB2PHYCFG0, GEVNT*, GFLADJ |
| Device (DEV) | `+0xC700` | DCFG, DCTL, DEVTEN, DSTS, DALEPENA |
| EP Commands | `+0xC800` | DEPCMDPAR2/1/0, DEPCMD (16 bytes x 8 EPs) |

### Key Global Registers

| Register | Offset | Important Bits |
|---|---|---|
| GCTL | `0xC110` | PRTCAPDIR[13:12]: 1=Host, 2=Device, 3=DRD; CORESOFTRESET[11]; DSBLCLKGTNG[0] |
| GSTS | `0xC118` | CURMOD[1:0]: 0=Device, 1=Host |
| GSNPSID | `0xC120` | Controller ID (expect `0x5533330B`) |
| GUSB2PHYCFG0 | `0xC200` | PHYSOFTRST[31]; USBTRDTIM[13:10]; PHYIF[3]; SUSPENDUSB20[6] |
| GFLADJ | `0xC630` | Frame length adjustment (default 0x20) |

### Key Device Registers

| Register | Offset | Important Bits |
|---|---|---|
| DCFG | `0xC700` | DEVSPD[2:0]: 0=HS, 1=FS; DEVADDR[10:3]; NUMP[29:25] |
| DCTL | `0xC704` | RUN_STOP[31]; CSFTRST[30]; ULSTCHNGREQ[8:5] |
| DEVTEN | `0xC708` | DISSCONNEVTEN[0]; USBRSTEVTEN[1]; CONNECTDONEEVTEN[2]; ULSTCNGEN[3] |
| DSTS | `0xC70C` | CONNECTSPD[2:0]; DEVCTRLHLT[22]; SOFFN[16:3] |
| DALEPENA | `0xC720` | Bit-per-endpoint active enable mask |

### USB Control Registers (outside DWC3, in CLKCTL_PER_MST)

| Register | Address | Purpose |
|---|---|---|
| PERIPH_CLK_ENA | `0x4903F00C` | Bit 20: USB peripheral clock gate |
| USB_GPIO0 | `0x4903F0A0` | USB GPIO control |
| USB_STAT0 | `0x4903F0A4` | USB status (read-only, likely VBUS detect) |
| USB_CTRL1 | `0x4903F0A8` | USB control register 1 |
| USB_CTRL2 | `0x4903F0AC` | Bit 8: PHY power-on-reset |

### Power Control Registers

| Register | Address | Bits | Purpose |
|---|---|---|---|
| VBAT PWR_CTRL | `0x1A609008` | Bit 16: UPHY_PWR_MASK (CLEAR=enable) | USB PHY power |
| VBAT PWR_CTRL | `0x1A609008` | Bit 17: UPHY_ISO (CLEAR=disable isolation) | PHY isolation |
| USB_CTRL2 | `0x4903F0AC` | Bit 8: PHY_POR (CLEAR=release reset) | PHY power-on-reset |

## Clocks

- **usb_clk**: 20MHz reference clock from PLL3 (480MHz) / 24 [S02, S08]
- **dwc_clk**: Gated `syst_pclk` (peripheral bus clock) [S02]
- **PLL3**: 480MHz — matches USB 2.0 HS data rate [S08]
- **Clock enable requires TWO register writes**: CGU_CLK_ENA[22] + PERIPH_CLK_ENA[20] [S07, S08]

| Register | Address | Bits | Purpose |
|---|---|---|---|
| CGU CLK_ENA | `0x1A602014` | Bit 22 | 20MHz USB reference clock |
| PERIPH_CLK_ENA | `0x4903F00C` | Bit 20 | USB peripheral clock gate |

## Power Control (Three Levels)

USB PHY power is controlled at three independent levels, all must be correct:

1. **AIPM Run Profile** (via SE/MHU): `phy_pwr_gating` bit 1 = USB_PHY_MASK, `ip_clock_gating` bit 6 = USB_MASK [S01, S07]
2. **VBAT Registers** (direct write): PWR_CTRL `0x1A609008` bits 16-17 [S01, S02, S08]
3. **CCPMST PHY POR** (direct write): USB_CTRL2 `0x4903F0AC` bit 8 [S01, S02, S08]

**Critical: Power bit polarity is inverted** — CLEAR bits to enable power/disable isolation. SET bits to disable/isolate. [S08]

## PHY Configuration

- **Interface**: UTMI+ (on-chip, no ULPI) [S08]
- **Width**: 16-bit (PHYIF=1, USBTRDTIM=5) or 8-bit (PHYIF=0, USBTRDTIM=9) [S08]
- **Linux DT**: `snps,hsphy_interface = "utmi"`, `phy_type = "utmi_wide"` [S02]
- **No separate PHY driver** — PHY is initialized by glue driver (Linux) or SoC init (Zephyr) [S02, S07]

## DMA Constraints

- DMA buffers must be in **bulk SRAM** (0x02000000 SRAM0 4MB, 0x08000000 SRAM1 2.5MB), NOT TCM [S08]
- Event buffers: 4096-byte aligned [S08]
- TRBs: 32-byte aligned [S08]
- On M55 cores, `local_to_global()` address translation required [S07, S08]
- D-cache coherency: explicit flush before DMA write, invalidate before DMA read [S08]
- `buserraddrvld` in GSTS set when USB DMA tries to access protected memory [S08]

## Pin Mux

USB_DP and USB_DM are dedicated analog pins — not routed through PINMUX. Only VBUS detection may use a GPIO (P15_4 as LPGPIO in Zephyr DTS overlay). [S08]

Physical connection on DevKit: "SoC USB" micro-B port (not PRG USB port). [S11]

## RAM Usage

Adding USB to the Linux kernel increases resource usage: [S11]
- xipImage: +0.2MB (1.6 -> 1.8MB)
- SRAM0: +864KB (1692KB -> 2556KB of 4096KB total)

## Open Questions

- ~~What is the exact PHY type?~~ Resolved: On-chip UTMI+ [S08]
- ~~What clock frequency does the PHY require?~~ Resolved: 20MHz ref clock [S02, S08]
- ~~Which power domains must be enabled?~~ Resolved: PD_SYST + three-level power control [S01, S07]
- What does USB_STAT0 at 0x4903F0A4 report? (likely VBUS detect state)
- What does USB_GPIO0 at 0x4903F0A0 control?

## Source References

[S01] TF-A, [S02] linux_alif, [S07] sdk-alif/zephyr_alif, [S08] TinyUSB/CMSIS-DFP, [S10] HWRM v2.8, [S11] Getting Started Guide — See [sources.md](sources.md)
