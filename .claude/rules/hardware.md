---
paths: ["**/*wifi*.c", "**/prj.conf", "**/sdkconfig.defaults", "**/wifi_prov_wifi_esp*"]
---
# Hardware Learnings

- **ESP32 WiFi power management blocks incoming TCP/ping** — ESP32 WiFi modem sleep (`wifi:pm start, type: 1`) causes the device to be unreachable for incoming TCP connections and ICMP pings, even though ARP resolves correctly. The radio sleeps between DTIM beacons and misses incoming packets.
- **WPA supplicant needs 8192+ system workqueue stack** — WPA supplicant operations like `wpa_cli_cmd_disconnect` require significant stack space. CONFIG_SYSTEM_WORKQUEUE_STACK_SIZE=4096 causes stack overflow (USAGE FAULT) when WiFi disconnect runs on the system workqueue. Use 8192 minimum when deferring WiFi operations to k_work on the system workqueue.
