---
paths: ["**/alif-flash/**", "**/alif_flash/**", "**/linux-boot-e7.json", "claude-mcps/alif-flash/**/isp.py", "claude-mcps/alif-flash/**/jlink.py"]
---
# Operational Learnings

- **alif-flash MCP: flash() resolves images from config_dir/../images/, not config dir** — The `flash()` tool in alif-flash MCP resolves binary file paths using this logic:
- **Always use J-Link (jlink_flash) for Alif E7 flashing, SE-UART as fallback only** — When flashing images to Alif E7 MRAM, ALWAYS use `jlink_flash()` (J-Link loadbin). Only fall back to `flash()` (SE-UART ISP) if jlink_flash fails.
