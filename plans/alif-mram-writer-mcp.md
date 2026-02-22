# Alif MRAM Writer MCP

Status: Complete
Created: 2026-02-20

## Problem

Flashing the Alif E7 requires communicating with the Secure Enclave over UART using a proprietary ISP protocol, plus running `app-gen-toc` to generate ATOC packages. The vendor tool `app-write-mram` is a PyInstaller binary that silently fails (exit 1, no output without `-v`), uses wrong default baud rate (55000 vs actual 57600), and requires non-obvious flags (`-p -b 57600`). We have working Python ISP scripts that prove the protocol is straightforward. An MCP server replaces the flaky vendor binary and integrates ATOC generation into a single workflow.

## Approach

Python MCP server (same pattern as `hw-test-runner`/`saleae-logic`). Direct port of working `alif-flash.py` ISP implementation. Uses `pyserial` for serial I/O, `mcp` SDK for MCP protocol. Shells out to `app-gen-toc` for ATOC generation (proprietary binary).

Changed from Rust to Python since all Alif tooling is Python-based and the existing ISP code already works.

## Tools

| Tool | Description |
|------|-------------|
| `list_ports` | List available `/dev/cu.usbmodem*` serial ports |
| `probe` | Check if SE-UART is responsive, report ISP/maintenance mode status |
| `maintenance` | Enter maintenance mode: START_ISP → SET_MAINTENANCE → RESET → verify |
| `gen_toc` | Run `app-gen-toc` to generate ATOC package from JSON config |
| `flash` | Write all images to MRAM from ATOC JSON config |

## Architecture

```
claude-mcps/alif-flash/
├── pyproject.toml
├── CLAUDE.md
├── src/alif_flash/
│   ├── __init__.py
│   ├── __main__.py    # Entry: parse args → logging → stdio_server
│   ├── server.py      # Tool definitions + dispatch (match/case)
│   └── isp.py         # ISP protocol: checksum, packets, serial I/O, commands
└── tests/
    └── test_isp.py    # Checksum, packet framing, response parsing tests
```

## ISP Protocol

Packet format: `[length] [cmd] [data...] [checksum]` where `checksum = (0 - sum(all_bytes)) & 0xFF`

Commands: START_ISP(0x00), STOP_ISP(0x01), DOWNLOAD_DATA(0x04), DOWNLOAD_DONE(0x05), BURN_MRAM(0x08), RESET_DEVICE(0x09), ENQUIRY(0x0F), SET_MAINTENANCE(0x16)

Responses: ACK(0xFE), DATA_RESPONSE(0xFD)

Reference implementation: `firmware/linux/alif-e7/setools/alif-flash.py`

## Verification

- [x] `pytest` passes — 18 tests (checksum, packet framing, response parsing, constants)
- [x] Registered in `.mcp.json`
- [x] CLAUDE.md written with tool documentation
- [x] Test `list_ports` and `probe` with board connected
- [x] Test `maintenance` + `flash` end-to-end (3.4MB, 672s, all 4 images OK)
