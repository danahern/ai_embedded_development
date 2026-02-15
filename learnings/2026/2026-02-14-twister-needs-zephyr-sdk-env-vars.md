---
title: Twister needs Zephyr SDK env vars in MCP subprocesses
date: 2026-02-14
author: danahern
tags: [testing, twister, build-system, macos]
---

MCP server subprocesses don't inherit shell profile env vars. Twister requires `ZEPHYR_TOOLCHAIN_VARIANT` and `ZEPHYR_SDK_INSTALL_DIR` to be set. The `zephyr-build` MCP auto-detects the SDK from `~/.cmake/packages/Zephyr-sdk/` (registered by `setup.sh`). If auto-detection fails, set these env vars in the MCP server's launch environment.
