---
paths: ["**/*wifi*.c", "**/prj.conf"]
---
# Hardware Learnings

- **WPA supplicant needs 8192+ system workqueue stack** — WPA supplicant operations like `wpa_cli_cmd_disconnect` require significant stack space. CONFIG_SYSTEM_WORKQUEUE_STACK_SIZE=4096 causes stack overflow (USAGE FAULT) when WiFi disconnect runs on the system workqueue. Use 8192 minimum when deferring WiFi operations to k_work on the system workqueue.
