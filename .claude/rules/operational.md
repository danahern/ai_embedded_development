---
paths: ["**/alif-flash/**", "**/alif_flash/**", "**/linux-boot-e7.json", "claude-mcps/alif-flash/**/isp.py", "claude-mcps/alif-flash/**/jlink.py"]
---
# Operational Learnings

- **Always use J-Link (jlink_flash) for Alif E7 flashing, SE-UART as fallback only** — When flashing images to Alif E7 MRAM, ALWAYS use `jlink_flash()` (J-Link loadbin). Only fall back to `flash()` (SE-UART ISP) if jlink_flash fails.
- **alif-flash MCP: flash() resolves images from config_dir/../images/, not config dir** — For config at `setools/linux-boot-e7.json`, images resolve from the parent dir's `images/` sibling (e.g., `alif-e7/images/`), NOT the `setools/` directory. Place bl32.bin, DTB, kernel, rootfs in `images/`. The ATOC package also resolves from the parent dir. `jlink_flash()` with a config uses the same resolution logic.
