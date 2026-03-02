# OSPI Flash Tool (UART-Based)

UART-based OSPI programming using a burner firmware on M55_HE + host PC application.

## Architecture

```
┌─────────────────┐  UART2 (RTS/CTS)  ┌──────────────────────┐
│  Host PC Tool   │ ◄──────────────► │  M55_HE Burner FW    │
│  (flashtool or  │    115200 or      │  (E8_dk_PC_Tool_     │
│   Python script)│    1000000 baud   │   Burner.bin, 48KB)  │
└─────────────────┘                    │                      │
                                       │  Synopsys SPI ctrl   │
                                       │       ▼              │
                                       │  ISSI IS25WX256      │
                                       │  NOR Flash @ 0xC0... │
                                       └──────────────────────┘
```

## Deployment

### Step 1: Load Burner via ATOC

Config: `RTSS-PC-tool-burner.json`
```json
{
    "RTSS-HE": {
        "binary": "E8_dk_PC_Tool_Burner.bin",
        "cpu_id": "M55_HE",
        "loadAddress": "0x58000000",
        "flags": ["load", "boot"],
        "signed": false
    }
}
```

```
alif-flash.gen_toc(config="RTSS-PC-tool-burner.json")
alif-flash.maintenance(jlink_reset=true)
alif-flash.flash(config="RTSS-PC-tool-burner.json")
# Reset board (J-Link NSRST or power cycle)
```

### Step 2: Switch to UART2

On E8 DevKit: Switch SW4 to UART2 position.
On E7 AppKit: Use separate UART2 FTDI cable.

### Step 3: Run Flash Tool

```bash
python3 flash_programming_cmdline.py \
  --board "Eagle A0 128MB" \
  --dfs 32 \
  --COM /dev/ttyUSB0 \
  --autoselectbaud 1 \
  --spispeed 5MHz \
  --spimode OCTAL \
  --file1 kernel.bin --address1 0xC0800000 \
  --file2 rootfs.bin --address2 0xC0000000
```

## Protocol Sequence

### 1. Baud Rate Negotiation

1. Host opens UART2 at **115200** baud
2. If auto-select enabled (`-asb 1`): host sends baud switch request
3. Host receives ACK bytes (`Ack try value:0`)
4. Both sides switch to **1000000** baud
5. If negotiation fails, stay at 115200

**Eagle A0 DevKit:** Baud MUST be fixed at 115200 — do not use auto-select.

### 2. Configuration Handshake

Host sends parameters, each ACKed by target:

| Step | Parameter | Log Entry |
|------|-----------|-----------|
| 1 | SPI Mode (OCTAL) | `Ack ReTrying SPIMODE:0` |
| 2 | DFS (32) | `Ack ReTrying DFS:0` |
| 3 | Chip ID query | `Ack ReTrying CHIPID:0` → target reports `ChipID: ISSI` |
| 4 | Encryption setting | `Ack ReTrying Encryption:0` |

### 3. File Transfer (per file, up to 5)

| Step | Parameter | Log Entry |
|------|-----------|-----------|
| 1 | File size | `Ack ReTrying file size:0` |
| 2 | Digits of file size | `Ack ReTrying digits of file size:0` |
| 3 | Destination address | `Ack ReTrying sending address:0` |
| 4 | Data blocks | Progress: `51%`, `86%`, `100%` |
| 5 | Completion ACK | Transfer complete |

Data is sent in blocks, DFS=32 (4-byte aligned, zero-padded if needed). Checksum verification included (algorithm unspecified in user guide).

### 4. Chip Erase (Optional)

Host sends chip erase command → target erases entire flash → ACK. ~150 seconds.

## Board Configuration (`.flash.cfg.xml`)

```xml
<TARGET>
    <board>Eagle A0 128MB</board>
    <flash>issi</flash>
    <start_address>0xC0000000</start_address>
    <size>128*1024*1024</size>
</TARGET>
```

All boards use ISSI flash at 0xC0000000. Sizes: 32MB, 64MB, 128MB.

## Target Binaries

| File | Size | Purpose |
|------|------|---------|
| `E8_dk_PC_Tool_Burner.bin` | 48 KB | Main burner — UART↔OSPI bridge |
| `set_flash_boot_E8_HE.bin` | 14 KB | Initialize OSPI XIP, boot M55_HE from flash |
| `set_flash_boot_E8_HP.bin` | 14 KB | Initialize OSPI XIP, boot M55_HP from flash |
| `set_flash_boot_E8_en_HE.bin` | 17 KB | Same + AES encryption support |
| `set_flash_boot_E8_en_HP.bin` | 17 KB | Same + AES encryption support |

## XIP Mode Handling

Added in v0.91: Burner checks if flash is in XIP mode. If so, exits XIP before programming. Flash cannot be programmed while in XIP mode.

## Adapting for E7

The burner binary is E8-specific. Potential issues on E7:

1. **XIP_SER register exists on E7 but removed on E8** — E8 burner may not set XIP_SER, which E7 needs for slave selection
2. **OSPI clock gate location differs** — E7 in MRAM controller space, E8 in CFGMST0
3. **SRAM1 address differs** — E7: 0x08000000, E8: 0x02400000

If E8 burner doesn't work on E7, a custom M55_HE firmware using the SDK's OSPI driver (`ospi_xip/source/ospi/ospi_drv.c`) + UART2 transport would be needed.
