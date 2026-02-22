---
paths: ["**/linux-boot-e7.json", "claude-mcps/alif-flash/**/isp.py", "claude-mcps/alif-flash/**/jlink.py"]
---
# Operational Learnings

- **alif-flash MCP: flash() resolves images from config_dir/../images/, not config dir** — The `flash()` tool in alif-flash MCP resolves binary file paths using this logic:
