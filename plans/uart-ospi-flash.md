# UART-Based OSPI Flash Programmer for Alif E7

**Status**: Todo

## Context

The E7 AppKit has IS25WX256 OSPI NOR flash at 0xC0000000 that needs faster programming than JLink FLM (~7 KB/s). RTT-based approach was attempted but RTT didn't work. Alif's E8 DevKit has a proven UART-based approach: a "burner" firmware on M55_HE receives data over UART2 and programs OSPI directly via the DWC SSI controller. Same concepts should work on E7 — same M55 cores, same DWC SSI controller, same ISSI flash.

**E8 tool performance**: ~30 KB/s at 1Mbaud — 4x faster than FLM. At 115200 baud (JLink VCOM limit): ~10 KB/s, still faster than FLM and no power cycles mid-transfer.

## Phase 1: Try E8 Burner Binary on E7

Quick experiment — load the E8 burner directly on E7.

### 1a. Create E7 burner ATOC config

**File**: `firmware/linux/alif-e7/setools/ospi-burner-e7.json`

```json
{
    "DEVICE": {
        "disabled": false,
        "binary": "app-device-config.json",
        "version": "0.5.00",
        "signed": true
    },
    "RTSS-HE": {
        "disabled": false,
        "binary": "E8_dk_PC_Tool_Burner.bin",
        "version": "1.0.0",
        "cpu_id": "M55_HE",
        "loadAddress": "0x58000000",
        "flags": ["load", "boot"],
        "signed": false
    }
}
```

Standalone — no TFA, no A32. Burner is the only thing running. UART2 pinmux already in app-device-config.json (P1_0 → RX, P1_1 → TX).

### 1b. Copy binary and flash

```
cp ~/Downloads/Eagle_A0_PC_Tool/Eagle_Target_bin/E8_dk_PC_Tool_Burner.bin \
   firmware/linux/alif-e7/setools/build/images/
alif-flash.gen_toc(config="build/config/ospi-burner-e7.json")
alif-flash.maintenance(jlink_reset=true)
alif-flash.flash(config="ospi-burner-e7.json")
# Power cycle
```

### 1c. Check if burner responds

```
alif-flash.monitor(baud=115200, duration=10)
```

JLink VCOM (`/dev/cu.usbmodem*`) maps to UART2 via J15 jumper (same port as Linux console). If burner sends anything, it works on E7.

**Success**: Recognizable output or responds to baud negotiation sequence.
**Failure**: Nothing on UART2 → Phase 3 (custom firmware).

## Phase 2: Python Host Tool

**File**: `claude-mcps/alif-flash/src/alif_flash/ospi_uart.py`

Implements the E8 flash tool's UART protocol using pyserial (already a dependency).

### Protocol (from E8 PDF documentation)

1. **Connect**: Open serial at 115200
2. **Baud negotiation**: Request 1000000, both switch. Fallback to 115200 if fails.
3. **SPI config**: Send board type, speed (5-50MHz), mode (OCTAL), DFS (32) — each ACKed
4. **File details**: Send count, per-file size + destination address — each ACKed
5. **Chip ID**: Target reads and reports JEDEC ID
6. **Prepare flash**: Target erases sectors, ACKs when ready
7. **Stream data**: Host sends chunks, each ACKed after target writes to flash
8. **Completion**: Target sends final checksum/status

### Module API

```python
class OspiUartProgrammer:
    def __init__(self, port: str, baud: int = 115200)
    def connect(self) -> str           # baud negotiate, return chip ID
    def configure(self, speed_mhz=25, mode="OCTAL", dfs=32) -> None
    def program(self, files: list[tuple[str, int]], progress_cb=None) -> dict
    def erase_chip(self) -> None
    def close(self)

    # High-level
    def flash_images(self, config_path: str, verify=True) -> dict
```

### Port discovery

```python
def find_vcom_port() -> list[str]:
    """Find JLink VCOM ports (UART2) — /dev/cu.usbmodem*"""
```

Different from SE-UART (`find_se_uart` uses `/dev/cu.usbserial*`). The `server.py` port resolver needs to route to the right port based on method.

### Key concern: JLink VCOM baud rate

JLink VCOM may cap at 115200. If so, effective throughput ~10 KB/s. An external USB-UART adapter on the UART2 header pins would enable 1Mbaud (~30 KB/s). Document both options.

## Phase 2b: Unit Tests

**File**: `claude-mcps/alif-flash/tests/test_ospi_uart.py`

Follow `test_ospi_rtt.py` pattern with MockSerial:

- Baud rate negotiation (success, fallback)
- SPI config exchange and ACK handling
- File details exchange
- Data chunking and progress callbacks
- Config parsing (skip MRAM entries, handle disabled)
- Error handling (NACK, timeout, serial errors)
- Port discovery

Target: ~25-30 tests.

## Phase 3: Custom M55_HE Firmware (if E8 binary fails)

Only needed if Phase 1 fails. Two sub-options:

### Option 3a: Custom firmware, same E8 protocol

Port TF-A's OSPI driver to bare-metal M55_HE firmware with UART2 transport implementing the same protocol the E8 burner uses. Python host tool stays the same.

**Directory**: `firmware/tools/ospi-programmer/`

Sources to port from `alif_arm-tf/plat/arm/board/devkit_e7/`:
- `drivers/ospi/ospi_drv.c` → OSPI controller driver
- `ospi_flash/norflash_ospi_setup.c` → flash init, erase, program
- `drivers/include/ospi_private.h` → register definitions

Key adaptations:
- `mmio_read/write` → `*(volatile uint32_t *)`
- Add UART2 init + TX/RX functions
- Command loop matching E8 protocol
- M55_HE memory: ITCM 0x00000000 (global 0x58000000), DTCM 0x20000000

### Option 3b: Custom firmware, simpler protocol

If reverse-engineering the E8 protocol proves difficult, design a minimal custom protocol:

```
Command:  [len:2][cmd:1][addr:4][data:N][crc16:2]
Response: [len:2][status:1][data:N][crc16:2]
```

Commands: PING(0x01), READ_ID(0x02), ERASE(0x03), WRITE(0x04), VERIFY(0x05)

Simpler to implement on both sides but requires writing both firmware and host tool from scratch.

## Phase 4: MCP Integration

**File**: `claude-mcps/alif-flash/src/alif_flash/server.py`

Add `method` parameter to `ospi_program` tool:

```python
"method": {"type": "string", "enum": ["uart", "rtt"], "default": "uart"},
"uart_port": {"type": "string", "description": "UART port (auto-detected)"}
```

Route to `ospi_uart.py` or `ospi_rtt.py` based on method. The `ospi_program` tool handles only the UART programming step (connect → program → close). ATOC switching is separate MCP calls.

## Phase 5: End-to-End Workflow

Full OSPI programming workflow (documented in CLAUDE.md):

```
# Step 1: Flash burner ATOC (one-time setup, or each OSPI update)
alif-flash.gen_toc(config="build/config/ospi-burner-e7.json")
alif-flash.maintenance(jlink_reset=true)
alif-flash.flash(config="ospi-burner-e7.json")
# Power cycle

# Step 2: Program OSPI via UART
alif-flash.ospi_program(config="linux-boot-e7-ospi-jlink.json", method="uart")

# Step 3: Restore Linux ATOC
alif-flash.gen_toc(config="build/config/linux-boot-e7-ospi.json")
alif-flash.maintenance(jlink_reset=true)
alif-flash.flash(config="linux-boot-e7-ospi.json")
# Power cycle → Linux boots from OSPI
```

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `claude-mcps/alif-flash/src/alif_flash/ospi_uart.py` | Create | UART flash protocol host module |
| `claude-mcps/alif-flash/tests/test_ospi_uart.py` | Create | Unit tests (~25-30) |
| `claude-mcps/alif-flash/src/alif_flash/server.py` | Modify | Add method param to ospi_program |
| `firmware/linux/alif-e7/setools/ospi-burner-e7.json` | Create | Burner ATOC config |
| `claude-mcps/alif-flash/CLAUDE.md` | Modify | OSPI UART workflow docs |

## Implementation Order

1. Phase 1 (hardware test) — try E8 binary
2. Phase 2 (Python host tool) — ospi_uart.py
3. Phase 2b (tests) — test_ospi_uart.py
4. Phase 4 (MCP integration) — server.py changes
5. Phase 5 (docs + hardware validation)

Phase 3 only if Phase 1 fails.

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| E8 binary incompatible with E7 | Need Phase 3 | Custom firmware using TF-A OSPI driver |
| JLink VCOM caps at 115200 | ~10 KB/s not 30 KB/s | External USB-UART adapter for 1Mbaud |
| Protocol docs incomplete | Missing framing details | Start with baud negotiation, iterate |
| UART2 routing wrong | Can't connect | Verify J15 jumper; try both ports |

## Reference

- E8 PC Tool: `~/Downloads/Eagle_A0_PC_Tool/`
- E8 PDF: `SPI_Flashing_Tool_User_guide_v1.2.pdf` (29 pages, full protocol docs)
- E8 burner binary: `Eagle_Target_bin/E8_dk_PC_Tool_Burner.bin` (48KB)
- E8 ATOC config: `config-files/RTSS-PC-tool-burner.json`
