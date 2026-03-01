# UART MCP Server

**Status**: Complete

## Context

Standalone MCP server for bidirectional UART communication — send commands, read responses, interact with serial consoles (Linux shells, U-Boot, AT modems, etc.). Session-based (open/send/close), generic (not Alif-specific).

## Solution

6-tool MCP server with session-based serial port management:

| Tool | Purpose |
|------|---------|
| `list_ports()` | List available serial ports with metadata |
| `open_port(port, baud?, settings?)` | Open a serial session, returns session_id |
| `close_port(session_id)` | Close a session and release the port |
| `send_command(session_id, command, timeout?, wait_for?)` | Send command, wait for response |
| `read_output(session_id, timeout?)` | Read any pending output (non-blocking drain) |
| `write_raw(session_id, data, hex?)` | Write raw bytes without waiting for response |

Response detection: idle timeout (default 0.5s) + optional regex prompt matching (`wait_for`). Echo filtering enabled by default.

## Implementation

```
claude-mcps/uart-mcp/
├── pyproject.toml
├── src/uart_mcp/
│   ├── __init__.py
│   ├── __main__.py
│   ├── server.py
│   └── serial_session.py
├── tests/
│   ├── test_serial_session.py  (22 tests)
│   └── test_server.py          (13 tests)
└── CLAUDE.md
```

## Verification

- [x] `pip install -e claude-mcps/uart-mcp` installs without errors
- [x] `python -m pytest claude-mcps/uart-mcp/tests/ -v` — all 35 tests pass
- [x] Registered in `.mcp.json`, tools appear in MCP tool list
- [x] End-to-end test: `list_ports` → `open_port` → `send_command` → `close_port` with Alif E8 Linux console on UART2
