# Flash Methods

## Method 1: SE-UART ISP (Persistent — Primary)

The Secure Enclave ISP protocol writes the ATOC package and images to MRAM. This is the **only method that produces persistent, SE-recognized writes**.

### How It Works

1. Host sends ISP commands over SE-UART (FTDI adapter, `/dev/cu.usbserial-*`)
2. `app-write-mram` forces device into maintenance mode (all application cores stopped)
3. Writes `AppTocPackage.bin` to system MRAM area
4. Writes each image to its `mramAddress` in application MRAM
5. Resets device — SE reads ATOC and boots normally

### Protocol

- **UART**: 57600 baud (default), 8N1, no flow control
- **Dynamic baud**: Bumps to 921600 during bulk transfers
- **Packet format**: `[length, cmd, data..., checksum]` (all bytes sum to 0 mod 256)
- **Data chunks**: 240 bytes with 2-byte LE sequence numbers
- **Segment limit**: 256KB per BURN_MRAM session (reconnect recovery for larger writes)

### ISP Commands

| Command | Code | Description |
|---------|------|-------------|
| START_ISP | 0x00 | Enter ISP mode |
| STOP_ISP | 0x01 | Exit ISP mode |
| DOWNLOAD_DATA | 0x04 | Send data chunk |
| DOWNLOAD_DONE | 0x05 | Data transfer complete |
| BURN_MRAM | 0x08 | Write downloaded data to MRAM |
| RESET_DEVICE | 0x09 | Reset target |
| ENQUIRY | 0x0F | Check ISP status |
| SET_MAINTENANCE | 0x16 | Enter maintenance mode |

### MCP Workflow

```
alif-flash.maintenance(jlink_reset=true)        # Enter maintenance mode
alif-flash.gen_toc(config="linux-boot-e7.json")  # Generate ATOC package
alif-flash.flash(config="linux-boot-e7.json")    # Write to MRAM
# Reset board (J-Link NSRST or power cycle)
```

### Characteristics

- **Speed**: ~5 KB/s (57600 baud, 240B chunks)
- **Persistent**: Yes — SE recognizes ATOC on every boot
- **Writes**: MRAM only (ATOC + images)
- **Limitations**: Slow (~25 min for 8MB), requires FTDI adapter, board must be ISP-responsive

---

## Method 2: J-Link loadbin (Non-Persistent — Debug)

J-Link connects to M55_HP via SWD and writes directly to memory-mapped regions. Fast but **writes are overwritten by SE on every power cycle** for ATOC-managed regions.

### How It Works

1. J-Link connects to `AE722F80F55D5_M55_HP` via SWD at AP[3]
2. For MRAM (0x80xxxxxx): direct memory writes via `loadbin` — no flash algorithm needed
3. For OSPI (0xC0xxxxxx): routes through `Ensemble_IS25WX256.FLM` flash algorithm
4. Custom JLinkScript overrides `ResetTarget()` to prevent SE boot disruption

### MRAM Addresses (E7)

| Component | Address | Typical Size |
|-----------|---------|-------------|
| TF-A (bl32) | 0x80002000 | ~30 KB |
| DTB | 0x80010000 | ~16-64 KB |
| Kernel (xipImage) | 0x80020000 | ~3.0 MB |
| RootFS (cramfs) | 0x80300000 | ~1.8 MB |

### MCP Workflow

```
alif-flash.jlink_flash(config="linux-boot-e7.json", verify=true)
# Reset board (J-Link NSRST or power cycle)
```

### Critical Gotchas

1. **NOT persistent** — SE reprograms ALL ATOC-managed images from its internal storage on every boot. J-Link writes succeed and verify OK, but are silently overwritten on reboot.
2. **JLinkScript mandatory** — without it, `loadbin` resets the SoC, killing AP[3] and making M55_HP inaccessible.
3. **File extension rejection** — JLinkExe rejects non-`.bin` files. Must copy `.dtb`/`.img` to `.bin` extension.
4. **Reset before first connect** — AP[3] must be alive (SE boot completed). J-Link NSRST or power cycle works.
5. **Reset after flash** — J-Link NSRST (via `reset_via_jlink()` or `ClrRESET`/`SetRESET`) triggers full SE re-boot with ATOC re-read. Physical power cycle also works but is not required.
6. **"Failed to halt CPU" is harmless** — M55_HP is running SE firmware, can't be halted, but writes succeed.

### Characteristics

- **Speed**: MRAM ~44 KB/s, OSPI ~7 KB/s (via FLM)
- **Persistent**: No (ATOC-managed regions overwritten on reboot)
- **Use case**: Temporary debugging, verifying images before committing via SE-UART

---

## Method 3: UART OSPI Flash Tool (Persistent OSPI)

A two-component system: burner firmware on M55_HE + host PC tool communicating over UART2.

### How It Works

1. Deploy burner firmware (`E8_dk_PC_Tool_Burner.bin`) to M55_HE via SE-UART/ATOC
2. Burner initializes UART2 and waits for host commands
3. Host sends baud negotiation → SPI config → file data over UART2
4. Burner programs OSPI NOR flash via Synopsys SPI controller

### Protocol Summary

1. Open UART2 at 115200 baud
2. Baud negotiation: request 1000000, both switch (or stay at 115200)
3. SPI config: mode (OCTAL), DFS (32), chip ID query
4. Per file: send size + destination address + data blocks
5. Target programs flash and ACKs each operation

### Deployment Config (`RTSS-PC-tool-burner.json`)

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

### Characteristics

- **Speed**: ~10 KB/s at 115200, ~30 KB/s at 1000000 baud
- **Persistent**: Yes (writes directly to OSPI flash)
- **Limitations**: Requires burner firmware loaded first, UART2 hardware flow control (RTS/CTS), E8-specific binary (E7 compatibility unconfirmed)

---

## Method 4: TF-A Program-from-MRAM (Boot-time OSPI)

TF-A's `init_nor_flash()` checks for a magic header at MRAM 0x8000E000 and programs OSPI at boot time.

### How It Works

1. Stage image data in MRAM via SE-UART
2. Write magic header (`0x4F535049` = "OSPI") at 0x8000E000 with dest address, length, src address
3. Reset board (J-Link NSRST or power cycle) — TF-A detects header, exits OSPI XIP, erases sectors, programs pages
4. TF-A clears magic to prevent re-programming on next boot
5. TF-A re-enters XIP mode and boots kernel from OSPI

### Header Format (at 0x8000E000)

```c
struct ospi_header {
    uint32_t magic;       // 0x4F535049 ("OSPI")
    uint32_t dest_addr;   // OSPI XIP address (0xC0xxxxxx)
    uint32_t length;      // Bytes to program
    uint32_t src_addr;    // MRAM source address
};
```

### Multi-Pass Configs

Large images are staged across multiple SE-UART passes:
- `ospi-pass-a-kernel.json` — stage kernel + OSPI header
- `ospi-pass-b-rootfs1.json` — stage rootfs part 1
- `ospi-pass-c-rootfs2.json` — stage rootfs part 2

### Characteristics

- **Speed**: Native OSPI controller speed (much faster than serial)
- **Persistent**: Yes (SE does not manage OSPI content directly)
- **Requires**: `FLASH_EN=1` in TF-A build
- **Limitations**: Requires staging in MRAM first (limited by MRAM size per pass)

---

## Method 5: FLM Flash Algorithms (via J-Link/Debugger)

Two FLM files shipped in the Alif CMSIS pack:

| FLM | Target | Flash Start | Size | Workspace RAM |
|-----|--------|-------------|------|---------------|
| `Ensemble.FLM` (10.3 KB) | MRAM | 0x80000000 | 5.5 MB | 128 KB @ 0x00000000 |
| `Ensemble_IS25WX256.FLM` (25.5 KB) | OSPI NOR | 0xC0000000 | 32 MB | 256 KB @ 0x00000000 |

FLMs are ARM ELF32 executables uploaded to target ITCM by the debugger. They implement `Init()`, `EraseSector()`, `ProgramPage()` per CMSIS Flash Algorithm interface. JLink automatically selects the correct FLM based on target address.

---

## Decision Matrix

| Question | Answer → Method |
|----------|----------------|
| Need persistent boot image update? | SE-UART ISP |
| Need persistent OSPI content? | TF-A program-from-MRAM or UART flash tool |
| Quick debug iteration on MRAM? | J-Link loadbin (temporary) |
| First-ever board setup? | SE-UART ISP (establishes ATOC) |
| ATOC needs to change? | SE-UART ISP (only method that writes ATOC) |
| Flashing Zephyr to M55? | SE-UART ISP (ATOC entry for M55_HP/HE) |
| OSPI via RTT? | **BROKEN** — M55_HP BusFault on OSPI controller access |
