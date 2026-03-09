# Plan: Add USB OSPI Programming Tool to alif-flash MCP

**Status:** Complete

## Context

The USB-to-OSPI flasher workflow is verified working (46.9 KB/s, ~5 min total cycle) but requires the AI to run `xmodem-send.py` via Bash, which has no way to detect completion. The XMODEM sender blocks until the transfer finishes, then the flasher firmware prints a success message and starts sending 'C' characters for another transfer. The AI can't see the output or know when to stop — the user had to manually cancel the Bash tool call.

### Current Pain Point

The XMODEM transfer output looks like:
```
[100%] 11843/11843 KB  47.1 KB/s  ETA 0s  block 94746/94746

Transfer complete: 12127460 bytes in 252.4s (46.9 KB/s)
Reading flasher status...

Success, 12127488 bytes received.
You may power down the board if you are done with programming.

Starting xmodemReceive... (flash sector_size=4096)
CCCCCCCCCCCCCCCCCCC
```

After "Success, N bytes received" the transfer is complete and the flasher loops back to waiting for another XMODEM ('C' characters). The Bash tool call never returns because xmodem-send.py's `read_status()` keeps reading the 'C' characters.

## Approach

Add an `ospi_program_usb` tool to the alif-flash MCP server that:
1. Auto-detects the Alif CDC-ACM device (VID 0x0525)
2. Runs the XMODEM-CRC protocol (128-byte blocks) in-process
3. Watches for "Success" in the flasher's post-transfer output
4. Returns structured result with transfer stats
5. Closes the port cleanly — no hanging on 'C' characters

### XMODEM Protocol (already implemented in xmodem-send.py)

- Standard XMODEM-CRC with 128-byte blocks (firmware doesn't support 1K)
- Wait for 'C' from receiver (CRC mode)
- SOH + seq + ~seq + 128 bytes + CRC16
- EOT at end, wait for ACK
- Pad last block with 0xFF

### Completion Detection

The key insight: after EOT/ACK, read serial output looking for the completion pattern:
```
Success, <N> bytes received.
```
Once this line appears, the transfer is confirmed successful. Stop reading immediately — don't wait for the 'C' characters that follow.

If "Error" or "CRC mismatch" appears instead, report failure with the error text.

Timeout after 10 seconds of no "Success" message post-EOT = transfer failed.

## Implementation

### New Tool: `ospi_program_usb`

**Parameters:**
- `image` (required): Path to binary image file (e.g., combined OSPI image)
- `device` (optional): Serial device path. Auto-detected from `/dev/cu.usbmodem*` matching VID 0x0525 if omitted
- `timeout` (optional, default: 600): Max transfer time in seconds

**Returns:**
```json
{
  "success": true,
  "bytes_sent": 12127460,
  "elapsed_seconds": 252.4,
  "speed_kbps": 46.9,
  "blocks": 94746,
  "flasher_message": "Success, 12127488 bytes received.",
  "device": "/dev/cu.usbmodem12001"
}
```

### Timeout & Error Detection Strategy

The tool has **four timeout layers**, each catching a different failure class:

| Timeout | Default | Detects |
|---------|---------|---------|
| **Receiver ready** | 30s | No 'C' from flasher — firmware didn't start, USB data path broken |
| **Per-block ACK** | 10s | No ACK/NAK for one block — flasher crashed mid-transfer, OSPI hung |
| **Post-EOT completion** | 30s | EOT ACK'd but no "Success" — final OSPI sector write failed |
| **Overall wall clock** | auto | Catch-all — calculated as `(file_size / 30000) * 2` seconds (2x worst-case speed) |

**Failure modes and detection:**

1. **No CDC-ACM device**: VID 0x0525 not in `ioreg` → immediate error: "No Alif CDC-ACM device found — is programming mode ATOC flashed and J2 connected?"

2. **No 'C' from receiver (30s)**: Flasher booted but XMODEM thread didn't start, or USB enumerated without data path. The flasher prints status text before 'C' — capture and include in error message for diagnosis.

3. **Per-block NAK**: Retry same block up to 10 times. If exhausted → error with block number. A single NAK is normal (USB noise); 10 consecutive NAKs means real data corruption.

4. **Per-block timeout (10s, no ACK or NAK)**: Flasher crashed or OSPI write hung on that sector. Normal ACK latency is <100ms. → error: "Flasher stopped responding at block N (offset 0xNNNN)"

5. **CAN from receiver**: Flasher detected unrecoverable error (bad sequence, protocol desync). → error: "Flasher cancelled at block N"

6. **Post-EOT silence (30s)**: EOT was ACK'd (all data received) but flasher never printed "Success". OSPI programming of final sector may have failed. → error: "Transfer completed but flasher didn't confirm OSPI write"

7. **"Error" in flasher output**: After EOT, flasher prints error text instead of "Success". → error with flasher's exact message

8. **Overall timeout**: Something unanticipated. Calculated automatically from file size — a 12MB file at worst-case 30 KB/s = 400s, ×2 = 800s. → error: "Transfer timed out after Ns"

**Completion detection** (the critical part):

After EOT/ACK exchange, read serial output character-by-character with 30s idle timeout. Accumulate into a buffer, scanning for:
- Line containing `"Success"` → **done, return success** with the full line as `flasher_message`
- Line containing `"Error"` or `"fail"` (case-insensitive) → **done, return failure** with error text
- Byte `0x43` ('C') appearing after any status text → flasher restarted XMODEM loop, we missed "Success" somehow → treat as success (data was received, flasher moved on)
- 30s with no data → **done, return failure** ("no confirmation")

### Implementation Details

1. **CDC-ACM auto-detection**: Enumerate `/dev/cu.usbmodem*`, filter by VID 0x0525 using `ioreg` parsing on macOS. Clear error if not found.

2. **XMODEM sender**: Port the logic from `xmodem-send.py` into `alif_flash/xmodem.py` as a reusable module. Pure Python, no external deps beyond `pyserial` (already a dependency).

3. **Progress reporting**: Log progress at 10% intervals via MCP logger. No need for real-time progress — the AI just needs to know when it's done.

4. **Port lifecycle**: Open port → transfer → read completion → close port. Never leave the port open on any code path (use try/finally).

### Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `alif-flash/src/alif_flash/xmodem.py` | Create | XMODEM-CRC sender module |
| `alif-flash/src/alif_flash/server.py` | Modify | Register `ospi_program_usb` tool |
| `alif-flash/tests/test_xmodem.py` | Create | Unit tests for XMODEM protocol (CRC, packet building, completion parsing) |
| `alif-flash/CLAUDE.md` | Modify | Document new tool |

### Testing Strategy

Unit tests (no hardware, mock serial port):
- CRC-16 CCITT calculation against known vectors
- Packet building (SOH + seq + data + CRC)
- Completion message parsing: "Success" → success, "Error" → failure, silence → timeout failure, bare 'C' after text → success
- CDC-ACM device detection logic (mock ioreg output, filter VID 0x0525 vs 0x1366)
- Last-block padding (0xFF fill)
- Per-block retry: 1 NAK then ACK → success; 10 NAKs → failure with block number
- Per-block timeout: mock no-response → failure with block offset
- CAN handling: mock CAN byte → failure
- Overall timeout calculation: verify formula matches file size

Integration test (manual, with hardware):
- Full transfer of combined image
- Verify flasher reports correct byte count
- Verify tool returns before flasher's next 'C' burst

### Workflow After Implementation

The AI can run the full cycle via MCP tools only:
```
1. gen_toc(config="linux-boot-e7-ospi-usbflash.json")
2. jlink_flash(config="linux-boot-e7-ospi-usbflash.json", verify=true)
   → Writes ATOC + images, resets board
3. ospi_program_usb(image="firmware/linux/alif-e7/images/ospi-combined.bin")
   → Auto-detects CDC-ACM, sends XMODEM, returns on "Success"
4. gen_toc(config="linux-boot-e7-mram.json")
5. jlink_flash(config="linux-boot-e7-mram.json", verify=true)
   → Restores normal boot ATOC
6. Open UART, verify Linux boots
```

No Bash calls, no manual cancellation needed.

## Time Estimates

| Task | Estimate |
|------|----------|
| Create xmodem.py module | 30 min |
| Add server tool registration | 15 min |
| Unit tests | 30 min |
| Integration test on hardware | 15 min |
| Documentation | 10 min |
| **Total** | **~1.5 hours** |

## Verification

- [x] Unit tests pass (CRC, packet build, completion parsing) — 47 tests, all passing
- [x] Tool auto-detects CDC-ACM device (VID 0x0525) — fixed ioreg parser to traverse full tree
- [x] Full XMODEM transfer completes and tool returns structured result — 12.1MB, 252.4s, 46.9 KB/s
- [x] Tool returns promptly after "Success" message (doesn't hang on 'C') — confirmed
- [x] Error cases handled: no device, no receiver ready, transfer failure — unit tested
- [x] Normal boot restored and Linux boots after USB programming cycle — "Linux Hello World" on UART2

## Bugs Found During Integration

1. **Stale ATOC**: `jlink_flash` writes whatever AppTocPackage.bin exists. Must run `gen_toc` before each `jlink_flash` when switching between configs. Documented in CLAUDE.md and README.md.
2. **CDC-ACM detection**: `ioreg -c IOUSBHostDevice` doesn't traverse deep enough — `IOCalloutDevice` is nested under `AppleUSBACMData > IOSerialBSDClient`. Fixed to use full `ioreg -l` traversal (commit `570d18a`).

## Implementation Notes

- `xmodem.py`: 366 lines, pure Python + pyserial
- `test_xmodem.py`: 47 tests covering CRC, packets, completion parsing, CDC detection, send protocol, timeouts
- `server.py`: Tool registration + `_ospi_program_usb` wrapper using `asyncio.to_thread`
- Build script: `build-tfa.sh --usb-init` for USB programming mode TF-A variant
- Full workflow documented in `firmware/linux/alif-e7/README.md` and `alif-flash/CLAUDE.md`
