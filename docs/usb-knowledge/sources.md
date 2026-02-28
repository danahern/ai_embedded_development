# Sources

Bibliography of all sources used to build this knowledge base. Every fact in the topic documents traces back to an entry here.

## Source Index

### [S01] trusted-firmware-a_alif
- **Type**: Git repo
- **Branch**: `alif_lts-v2.10.8`
- **Location**: https://github.com/alifsemi/trusted-firmware-a_alif
- **Extracted**:
  - USB PHY power enable sequence in `service_enable_usb_phy()`
  - AIPM service call mechanism (service IDs 310/311 for get/set run profile)
  - MHU v2 message passing (Send 0x1B800000, Recv 0x1B810000, Payload 0x02380000)
  - `run_profile_t` structure: `phy_pwr_gating` bit 1 = USB_PHY
  - No runtime SMC/PSCI call for USB -- init is one-shot at boot
  - VBAT PWR_CTRL register writes (0x1A609008 bits 16-17)
  - USB_CTRL2_PHY_POR register (0x4903F0AC bit 8)
- **Key Findings**:
  - TF-A performs USB PHY power-up before Linux via SE service + direct register writes
  - Three-level power control: AIPM profile, VBAT registers, PHY POR
  - This is the critical "hidden prerequisite" for Linux USB probe success

### [S02] linux_alif (APSS-v2.1.0 branch)
- **Type**: Git repo
- **Branch**: `APSS-v2.1.0`
- **Location**: https://github.com/alifsemi/linux_alif
- **Extracted**:
  - `dwc3-ensemble.c` glue driver: compatible "alif,ensemble-usb3", power_control() sequence
  - Device tree: wrapper hsusb node + child dwc3 node, dr_mode="peripheral", disabled by default
  - Clock driver: USB clock = PLL3/24 = 20MHz (ENSEMBLE_USB_CLK), DWC clock = gated syst_pclk
  - Defconfig: `CONFIG_USB_SUPPORT is not set` by default
  - GIC SPI 26 interrupt
  - No PHY driver -- raw ioremap() in glue driver
  - DT quirk properties: dis_u3_susphy, dis_u2_susphy, usb2-lpm-disable
- **Key Findings**:
  - USB is disabled by default in both DT and defconfig
  - Glue driver does PHY power via raw register writes (not PHY framework)
  - Regulator mismatch: driver requests vdd33/vdd18 but DT doesn't wire them

### [S03] linux_alif (v6.12-dev branch)
- **Type**: Git repo
- **Branch**: `v6.12-dev`
- **Location**: https://github.com/alifsemi/linux_alif
- **Extracted**:
  - DT node name changes: `dwc3-drd@` -> `dwc3@`, `usbdual_hs: usb-dual@` -> `dwc3: usb@`
  - Otherwise identical USB code to APSS-v2.1.0
- **Key Findings**:
  - No functional USB changes between branches -- cosmetic DT naming only

### [S04] meta-alif-ensemble
- **Type**: Git repo (Yocto layer)
- **Branch**: `scarthgap`
- **Location**: https://github.com/AlifSemi/meta-alif-ensemble
- **Extracted**:
  - Three USB kernel config fragments: usb.cfg (gadget), usb_host.cfg (host), usb_boot.cfg (USB boot)
  - DCT mechanism: HSUSB_STATUS set to "okay" when USB feature enabled
  - CONFIG_USB_DWC3_GADGET=y + CONFIG_USB_G_SERIAL=y for gadget mode
  - CONFIG_USB_DWC3_HOST=y + CONFIG_USB_XHCI_HCD=y for host mode
  - dr_mode hardcoded to "peripheral" in DTSI -- no override for host mode
  - vdd33-supply/vdd18-supply not wired to USB node in board DTS
- **Key Findings**:
  - No ADB, no ConfigFS, no ECM/RNDIS -- only g_serial for gadget
  - Config fragment conflict: gadget+host simultaneously would break (mutually exclusive Kconfig)
  - dr_mode never changes to "host" even with host config fragments

### [S05] meta-alif
- **Type**: Git repo (Yocto distro layer)
- **Branch**: `scarthgap`
- **Location**: https://github.com/AlifSemi/meta-alif
- **Extracted**:
  - DISTRO_FEATURES: apss-usb (gadget), apss-usb-host (host), apss-usb-boot (USB boot)
  - BASE_IMAGE system: IMAGE=1,2,3,4,6 enable apss-usb; IMAGE=7 enables apss-usb-boot
  - apss-usb-host is NEVER auto-enabled by any BASE_IMAGE preset
- **Key Findings**:
  - USB host mode requires manual DISTRO_FEATURES addition
  - Default builds use gadget mode (g_serial) only

### [S06] alif_linux-apss-build-setup
- **Type**: Git repo (build scripts)
- **Branch**: `scarthgap_yocto_5.0`
- **Location**: https://github.com/alifsemi/alif_linux-apss-build-setup
- **Extracted**:
  - Layer manifest, kernel/TF-A branch configuration
  - Machine configs (devkit-e8, appkit-e8), BASE_IMAGE variable system
  - SDK/toolchain: apss-tiny distro, cortexa32hf-neon target
- **Key Findings**:
  - Confirms build system architecture and USB config flow via DISTRO_FEATURES

### [S07] sdk-alif / zephyr_alif / hal_alif
- **Type**: Git repos (Zephyr SDK)
- **Location**: https://github.com/alifsemi/sdk-alif (manifest), zephyr_alif (kernel fork), hal_alif (HAL)
- **Extracted**:
  - Zephyr DWC3 UDC driver (`udc_dwc3.c`): PHY reset sequence, UTMI config, Alif local_to_global() DMA quirk
  - DT node: `usb@48200000`, compatible "snps,dwc3", reg size 0xCA04, IRQ 101
  - AIPM structures: `run_profile_t` with ip_clock_gating (USB=bit6), phy_pwr_gating (USB_PHY=bit1)
  - SE service IDs: GET_RUN=310, SET_RUN=311
  - MHU message format: `service_header_t` + payload fields
  - Power domains: USB in PD_SYST (PD6)
  - Clock macros: ALIF_USB_CLK = PERIPH_CLK_ENA bit 20 + CGU_CLK_ENA bit 22
  - SoC init: VBAT_PWR_CTRL clear bits 16,17; EXPMST_USB_CTRL2 clear bit 8
- **Key Findings**:
  - Zephyr approach matches Linux but uses proper clock/power-domain frameworks
  - DMA requires local-to-global address translation on M55 cores
  - Complete AIPM protocol definition for USB power control

### [S08] alif_tinyusb-examples (TinyUSB Alif fork + CMSIS DFP)
- **Type**: Git repos
- **Location**: https://github.com/alifsemi/tinyusb (branch: alif), https://github.com/alifsemi/alif_ensemble-cmsis-dfp
- **Extracted**:
  - Complete bare-metal USB init sequence (14 steps from clock enable to enumeration)
  - Full DWC3 register map: GBL (0xC100+), DEV (0xC700+), EP CMD (0xC800+)
  - Controller ID: GSNPSID = 0x5533330B (DWC_usb3 release 3.30b)
  - PHY config: 16-bit UTMI+ (USBTRDTIM=5), or 8-bit (USBTRDTIM=9)
  - Event buffer: 4096 bytes, 4KB-aligned, in bulk SRAM (not TCM)
  - TRB structure: 16 bytes (buf_ptr, size, ctrl with HWO/LST/CHN/CSP/TRBCTL)
  - EP command types: DEPCFG(1), DEPXFERCFG(2), DEPSTRTXFER(6), DEPENDXFER(8), DEPSTARTCFG(9)
  - USB IRQ = 101, max packet sizes (HS=512, FS=64, ISOC=1024)
  - Shutdown sequence: assert PHY POR, enable isolation, mask power, disable clock
  - DMA must use bulk SRAM (0x02000000 or 0x08000000), not TCM
- **Key Findings**:
  - No SE/AIPM calls needed for bare-metal USB -- direct register control only
  - PHY power polarity: CLEAR bits to enable (inverted from intuition)
  - D-cache coherency required for all DMA buffers
  - Definitive init sequence that works on real hardware

### [S09] SE Host Services API (AUGD0014)
- **Type**: PDF (Alif documentation)
- **Version**: Referenced from TF-A/SDK
- **Extracted**:
  - Power services: `SERVICES_get_run_cfg` / `SERVICES_set_run_cfg` (run_profile_t)
  - Clock services: `SERVICES_clocks_enable_clock(CLKEN_USB)` -- dedicated USB clock enable
  - Clock enum: CLKEN_USB among CLKEN_SYSPLL, CLKEN_CPUPLL, CLKEN_ES0, etc.
  - Power profiles: LOWEST_POWER, HIGH_PERFORMANCE, USER_SPECIFIED, DEFAULT
  - Memory retention config, corestone standby mode
- **Key Findings**:
  - SE provides a fourth clock enable path (CLKEN_USB) beyond the three register-level controls
  - Run profile API is the official SE interface matching TF-A's service ID 310/311

### [S10] HWRM v2.8 (Hardware Reference Manual)
- **Type**: PDF (Alif documentation)
- **Pages read**: 1186-1252 (USB programming guide + register maps)
- **Extracted**:
  - USB programming model: device mode init, host mode init, transfer setup
  - Event buffer architecture: GEVNTADR0/GEVNTSIZ0/GEVNTCOUNT0 circular buffer
  - Transfer state machine: Start -> In Progress -> Complete
  - xHCI CAP registers: CAPLENGTH(0x0), HCSPARAMS1-3, HCCPARAMS1-2
  - GBL registers: GCTL (PRTCAPDIR, CORESOFTRESET, DSBLCLKGTNG), GSTS (CURMOD)
  - External USB registers: USB_GPIO0, USB_STAT0, USB_CTRL1, USB_CTRL2
  - Hardware params: MAXPORTS=1, MAXINTRS=1, MAXSLOTS=64, FIFO 1865x64-bit
- **Key Findings**:
  - Complete register-level programming reference for host and device modes
  - xHCI version 1.1, USB 2.0 HS only despite DWC3 naming

### [S11] Getting Started with Linux Pre-Built Images (AUGD0003 v0.5.2_3)
- **Type**: PDF (Alif documentation)
- **Version**: v0.5.2_3, July 2024
- **Location**: docs/alif-e7/AUGD00013-Getting-Started-with-Linux-Prebuilt-Images-v0.5.2_3.pdf
- **Extracted**:
  - USB device detection log: VID=0525, PID=a4a7, "Gadget Serial v2.4"
  - Host sees: /dev/ttyACM0 (CDC ACM), Target sees: /dev/ttyGS0
  - USB adds 0.2MB to xipImage (1.6->1.8MB), uses 2556KB SRAM0 (vs 1692KB baseline)
  - Connection: USB-B micro from "SoC USB" port on DevKit
  - Complete kernel config list for USB device support
  - DT snippet showing working config (status="okay")
  - DISTRO_FEATURES table: DWC3+USB_GADGET+CDC-ACM enabled via "apss-usb"
  - Mass storage detection log (host mode): xhci-hcd, /dev/sda
  - MRAM operation supports: SD-share, USB, I2C, SPI, CRC, GDB debug
- **Key Findings**:
  - Confirmed working USB gadget serial on real hardware with these specific configs
  - USB RAM overhead is significant (~864KB additional SRAM0 usage)
  - Physical connection uses "SoC USB" micro-B port on DevKit (not PRG USB)

### [S12] sdk-containers
- **Type**: Git repo (Docker build containers)
- **Location**: https://github.com/alifsemi/sdk-containers
- **Extracted**: No USB-relevant content
- **Key Findings**: Build infrastructure only, no USB configuration

### [S13] Conversation History (Debugging Sessions)
- **Type**: Previous Claude Code sessions (~80 conversations)
- **Location**: Project conversation history
- **Extracted**:
  - DCTL register debugging: offset 0xC704, bit 31 = Run/Stop, practical debug sequence
  - GHWPARAMS0 at offset 0xC140: bits 2:0 = 2 → Device-Only mode, no OTG, VBUS detection irrelevant
  - SE AIPM service ID off-by-one bug: local headers had GET=311/SET=312 (wrong), correct is GET=310/SET=311
  - DWC3 "Failed to get clk 'ref': -2" is non-fatal, UDC works despite it
  - ConfigFS vs legacy FUNCTIONFS Kconfig distinction
  - HSUSB_STATUS DevKit="disabled" vs AppKit="okay" — silent USB disable on wrong board
  - ConfigFS mount timing race at boot — script runs before configfs mounted
  - J1 (device port) vs J2/PRG_USB (FTDI ISP only) port confusion
  - g_serial auto-binds UDC, must force-disable via sed in do_configure_append
  - OOM with full USB stack on 4MB SRAM — kernel panic
  - PHY init in pinctrl-devkit.c, not just DWC3 glue
  - All USB built-in (=y), not modules — no kernel-module packages for E7
  - Yocto OE zeus syntax: underscores not colons
  - BusyBox `head -n 1` not `head -1`
  - macOS requires pure CDC-ECM, no RNDIS
  - appkit-e7-flatboard.dts is the correct DTS (not appkit-e7.dts)
- **Key Findings**:
  - Practical debugging arc from build → PHY → SE AIPM → working USB
  - Many gotchas only discoverable through hands-on debugging
  - Service ID off-by-one is especially dangerous — crashes SE silently
