# OSPI Controller & ISSI Flash Reference

## Controller: Synopsys DWC SSI

Two independent instances, each with a dedicated AES engine:

| Resource | Base Address |
|----------|-------------|
| OSPI0 registers | 0x83000000 |
| AES0 registers | 0x83001000 |
| OSPI1 registers | 0x83002000 |
| AES1 registers | 0x83003000 |
| OSPI0 XIP window | 0xA0000000 (512 MB, HyperRAM on DevKit) |
| OSPI1 XIP window | 0xC0000000 (512 MB, NOR Flash on DevKit) |

FIFO depth: 256 entries TX, 256 entries RX.

## Key Registers

| Offset | Name | Description |
|--------|------|-------------|
| 0x00 | CTRLR0 | Frame format, transfer mode, DFS, SPI mode, clock polarity |
| 0x04 | CTRLR1 | Data frames to receive (N-1) |
| 0x08 | SSIENR | Enable: 1=enable, 0=disable. **Must disable before config changes** |
| 0x10 | SER | Slave Enable (chip select bitmask) |
| 0x14 | BAUDR | Baud rate: `sclk_out = AXI_clock / BAUDR` (even, >= 2) |
| 0x28 | SR | Status: BUSY, TF_NOT_FULL, TF_EMPTY, RF_NOT_EMPT, etc. |
| 0x4C | DMACR | DMA control: bit 1 = RX DMA, bit 2 = TX DMA |
| 0x60 | DR[0] | Data register (TX/RX FIFO access) |
| 0xF0 | RX_SAMPLE_DLY | RX sample delay (clock cycles before sampling) |
| 0xF4 | SPI_CTRLR0 | Enhanced SPI: DDR, addr length, wait cycles, inst length |
| 0xF8 | TXD_DRIVE_EDGE | DDR transmit drive edge |
| 0x100 | XIP_INCR_INST | XIP INCR transfer opcode |
| 0x104 | XIP_WRAP_INST | XIP WRAP transfer opcode |
| 0x108 | XIP_CTRL | XIP control register |
| 0x10C | XIP_SER | XIP slave enable (E7 only — **removed on E8**) |

## CTRLR0 Fields

| Field | Bits | Key Values |
|-------|------|------------|
| DFS | [4:0] | 0x07=8-bit, 0x0F=16-bit, 0x1F=32-bit |
| FRF | [7:6] | 0=SPI, 1=SSP, 2=Microwire |
| SCPH/SCPOL | [8:9] | Clock phase/polarity |
| TMOD | [11:10] | 0=TX+RX, 1=TX Only, 2=RX Only, 3=EEPROM Read |
| SPI_FRF | [23:22] | 0=Standard, 1=Dual, 2=Quad, 3=Octal |
| SPI_HE | [24] | HyperBus enable |
| SSI_IS_MST | [31] | Master mode |

## SPI_CTRLR0 Fields (Enhanced SPI)

| Field | Bits | Description |
|-------|------|-------------|
| TRANS_TYPE | [1:0] | 0=Standard (cmd single), 2=FRF-defined (all multi-line) |
| ADDR_L | [6:2] | 0x0=0-bit, 0x2=8-bit, 0x6=24-bit, 0x8=32-bit |
| INST_L | [9:8] | 0=0-bit, 1=4-bit, 2=8-bit, 3=16-bit |
| WAIT_CYCLES | [15:11] | Dummy cycles between address and data |
| SPI_DDR_EN | [16] | DDR for address+data |
| INST_DDR_EN | [17] | DDR for instruction |
| SPI_RXDS_EN | [18] | Read Data Strobe enable |

## ISSI IS25WX256 Commands

### Identification

| Command | Opcode | Description |
|---------|--------|-------------|
| READ_ID | 0x9E | Read JEDEC ID (device_id = 0x9D for ISSI) |
| RESET_ENABLE | 0x66 | Reset enable |
| RESET_MEMORY | 0x99 | Reset memory |

### Status/Config

| Command | Opcode | Description |
|---------|--------|-------------|
| READ_STATUS_REG | 0x05 | Read status register (bit 0 = WIP) |
| READ_FLAG_STATUS_REG | 0x70 | Read flag status register |
| READ_VOLATILE_CONFIG_REG | 0x85 | Read volatile config |
| WRITE_VOLATILE_CONFIG_REG | 0x81 | Write volatile config |
| WRITE_ENABLE | 0x06 | Set WEL bit (required before every write/erase) |
| WRITE_DISABLE | 0x04 | Clear WEL bit |

### Read

| Command | Opcode | Description |
|---------|--------|-------------|
| 4BYTE_READ | 0x13 | Standard read, 4-byte address |
| 4BYTE_FAST_READ | 0x0C | Fast read, 4-byte address |
| 4BYTE_OCTAL_IO_FAST_READ | 0xCC | Octal I/O fast read |
| DDR_OCTAL_IO_FAST_READ | 0xFD | DDR Octal I/O fast read (XIP) |

### Erase

| Command | Opcode | Size | Description |
|---------|--------|------|-------------|
| SECTOR_ERASE_4KB | 0x21 | 4 KB | 4-byte address |
| BLOCK_ERASE_32KB | 0x5C | 32 KB | 4-byte address |
| BLOCK_ERASE_64KB | 0xDC | 64 KB | 4-byte address |
| CHIP_ERASE | 0xC7 / 0x60 | Full | Entire chip (~150s) |

### Program

| Command | Opcode | Description |
|---------|--------|-------------|
| PAGE_PROGRAM | 0x12 | 4-byte address, up to 256 bytes per page |

### Volatile Config Register Addresses

| Register | Address | Value | Effect |
|----------|---------|-------|--------|
| Mode | 0x00 | 0xE7 | Octal DDR + DQS |
| Wait cycles | 0x01 | 16 | Default dummy cycles |
| Wrap config | 0x07 | 0xFD | 32-byte wrap |

## Initialization Sequence

```
1. enable_ospi_clk()                    # Enable OSPI clock gate
2. Disable XIP (AES control register)   # aes_control &= ~XIP_EN
3. Disable controller (ssienr = 0)
4. Clear slave enable (ser = 0)
5. Set rx_sample_dly = 4
6. Set txd_drive_edge = 1
7. Set aes_rxds_delay = 11
8. Set baud: baudr = AXI_clock / ospi_clock
9. Enable controller (ssienr = 1)

10. Probe flash in SDR mode:
    a. Read Device ID (0x9E) — verify 0x9D
    b. Write Enable (0x06)
    c. Set wrap 32-byte (volatile reg 0x07 = 0xFD)
    d. Write Enable
    e. Set wait cycles (volatile reg 0x01 = 16)
    f. Write Enable
    g. Switch to Octal DDR+DQS (volatile reg 0x00 = 0xE7)

11. Switch driver to ddr_en = 1

12. Enter XIP mode:
    a. Configure XIP_CTRL for Octal DDR
    b. Set xip_incr_inst = 0xFD (DDR Octal IO Fast Read)
    c. Enable XIP via AES: aes_control |= XIP_EN
```

## XIP Enable/Disable

**XIP is controlled through the AES module, not the OSPI controller directly.**

```c
// Enable XIP
aes_regs->aes_control |= (1 << 4);  // AES_CONTROL_XIP_EN

// Disable XIP
aes_regs->aes_control &= ~(1 << 4);
```

### XIP Exit (from non-volatile XIP mode)

Set `xip_mode_bits = 0x1`, toggle XIP enable on/off to force flash out of continuous-read mode:
```c
aes_regs->aes_control |= XIP_EN;   // Enable
aes_regs->aes_control &= ~XIP_EN;  // Immediately disable
```

## Programming Sequence (Erase + Write)

```
1. Exit XIP mode (disable AES XIP_EN)
2. Write Enable (0x06)
3. Sector Erase (0x21/0xDC + 4-byte address)
4. Poll Status Register (0x05) until WIP bit (bit 0) clears
5. Write Enable (0x06)
6. Page Program (0x12 + 4-byte address + up to 256 bytes)
7. Poll Status Register until WIP clears
8. Repeat steps 5-7 for remaining pages
9. Re-enter XIP mode (configure XIP_CTRL + enable AES XIP_EN)
```

## Transfer Pattern

All register changes require disable→configure→enable:
```c
spi_disable(cfg);          // ssienr = 0
// ... configure CTRLR0, SPI_CTRLR0, BAUDR, etc. ...
spi_enable(cfg);           // ssienr = 1
```

## Blocking Send

```c
ospi_writel(cfg, data_reg, data);       // Push to TX FIFO
ospi_writel(cfg, ser, cfg->ser);        // Assert chip select
while ((sr & (SR_TF_EMPTY | SR_BUSY)) != SR_TF_EMPTY) { }  // Wait
```

## Clock Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| OSPI_CLOCK | 100 MHz | sclk_out frequency |
| WAIT_CYCLES | 16 | Dummy cycles for reads |
| RX_SAMPLE_DELAY | 4 | Internal clock cycles before sampling |
| DDR_DRIVE_EDGE | 1 | TX data driving edge |
| AES_RXDS_DELAY | 11 | Read Data Strobe delay |

Baud divider: `BAUDR = GetSystemAXIClock() / OSPI_CLOCK` (e.g., 400MHz / 100MHz = 4).

## Two Driver Layers in SDK

1. **XIP Sample Driver** (`ospi_xip/source/`) — minimal, self-contained, polling-only, ISSI-specific. Best reference for init sequence.
2. **CMSIS OSPI Driver** (`drivers/source/ospi.c`) — full-featured, generic, supports interrupts + DMA + HyperBus. Best reference for DMA patterns.

## Pin Configuration (OSPI1 on DevKit)

| Signal | Port.Pin | Alt Function |
|--------|----------|-------------|
| Data[0:3] | P9.5-7, P10.0 | AF1 |
| Data[4:7] | P10.1-4 | AF1 |
| SCLK | P5.5 | AF1 |
| SCLKN | P8.0 | AF1 |
| CS | P5.7 | AF1 |
| RXDS | P10.7 | AF7 |
| Flash Reset | P15.7 | GPIO output |
