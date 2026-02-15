# ESP-IDF Crash Analysis

Status: Ideation
Created: 2026-02-15

## Problem

ESP-IDF has its own coredump format (different from Zephyr). Currently `analyze_coredump` only handles Zephyr's `#CD:` prefixed format. ESP32 crashes require manual analysis with `espcoredump.py` or similar tooling outside the MCP workflow.

## Approach

Could extend `analyze_coredump` to detect and handle ESP32 core dumps, or add a separate `analyze_esp_coredump` tool to the embedded-probe MCP. ESP-IDF coredumps can be stored in flash or emitted via UART — the tool would need to handle both retrieval methods.
