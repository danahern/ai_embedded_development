# E7 vs E8 Differences (Flashing Impact)

## OSPI IP Changes (Critical)

| Aspect | E7 (E1/E3/E5/E7) | E8 (E4/E6/E8) |
|--------|-------------------|----------------|
| OSPI IP version | Original | **Updated to 2.01** |
| XIP_SER register | Exists (manual slave select) | **Removed** — address-based slave select |
| Slave selection | Manual via XIP_SER register | Bit 28 of address: 0xA/0xC... = slave 0, 0xB/0xD... = slave 1 |
| XIP_WRITE_CTRL | Basic | New `XIPWR_DFS_HC` bit for hard-coded DFS |
| DDR memory writes | Unaligned/narrow may fail | **Fixed** via XHB-500 bridge insertion |
| Multi-bus-master | Limited | **Supported** for external RAM |
| OSPI clock gate | In MRAM controller | **Moved to CFGMST0 at 0x4902_F03C** (not enabled by default!) |

**Implication:** Code that writes to XIP_SER will **fault on E8** (register doesn't exist). E8 burner firmware does NOT use XIP_SER. E7 firmware MUST use XIP_SER for slave selection.

## Memory Map Differences

| Region | E7 | E8 |
|--------|----|----|
| SRAM1 base | 0x0800_0000 (2.5 MB) | **0x0240_0000** (4 MB) |
| SRAM6-9 | Available (~5 MB) | **Removed** |
| Total on-chip RAM | ~13.5 MB | ~9.75 MB |
| OSPI memory alias | Standard | Extra aliases at 0x2000_0000 |

## Clock Differences

| Aspect | E7 | E8 |
|--------|----|----|
| HCLK/PCLK source | Derived from ACLK | **Derived from SYSPLL** |
| OSPI clock enable | In MRAM controller regs | **CFGMST0 at 0x4902_F03C** |
| SPI latency | Normal | **Higher** (clock domain crossing) |

## Board/Flashing Differences

| Aspect | E7 AppKit | E8 DevKit (DK-E8) |
|--------|-----------|-------------------|
| SE-UART interface | Dual FTDI cables | **Single USB-C** (PRG USB) with SW4 switch |
| UART selection | Fixed (separate ports) | **SW4**: default=SEUART, pos 2=UART2, pos 3=UART4 |
| Debug probe | External J-Link | **On-board J-Link E1** (fw V8.88+) |
| MRAM base (detected) | 0x80000000 | 0x801C0000 |
| SE baud rate | 57600 | 55000 |
| Flash part | ISSI IS25WX256 | ISSI (same family) |

## Porting Risks: E8 Flash Tools → E7

| Risk | Impact | Mitigation |
|------|--------|------------|
| XIP_SER access faults on E8 | E7 code with XIP_SER works; E8 binaries on E7 may skip slave select | Conditional compilation or separate binaries |
| OSPI clock not enabled | E8 clock at new register, E7 at old location | Check both locations or use SDK abstractions |
| SRAM1 address shift | Burner using SRAM1 buffers at wrong address | Use only TCM (ITCM/DTCM) for portability |
| SRAM6-9 gone on E8 | Not available for large buffers on E8 | Use SRAM1 instead |
| Single UART sharing on E8 | Must switch SW4 between SEUART and UART2 | No issue on E7 (separate cables) |

## ATOC Config Differences

| Field | E7 | E8 |
|-------|----|----|
| `global-cfg.db` Revision | B4 | A0 |
| `global-cfg.db` Part# | AE722F80F55D5LS | AE822FA0E5597LS0 |
| DTB file | appkit-e7.dtb | devkit-e8.dtb |
| Rootfs address | 0x80300000 | 0x80380000 |
| JLink device name | AE722F80F55D5_M55_HP | AE822FA0E5597_M55_HP |

## Key Takeaway

The E7 and E8 share the same fundamental architecture but differ in OSPI IP version, SRAM layout, and clock domains. Flash tooling written for one must account for:
1. XIP_SER presence/absence
2. OSPI clock gate register location
3. SRAM1 base address
4. `global-cfg.db` device matching
