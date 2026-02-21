---
paths: ["**/*wifi*.c", "**/app-*-config*.json", "**/linux-boot-e7.json", "**/meta-eai/**", "**/prj.conf", "**/sdkconfig.defaults", "**/usb-ecm*.bb", "**/wifi_prov_wifi_esp*"]
---
# Hardware Learnings

- **ESP32 WiFi power management blocks incoming TCP/ping** — ESP32 WiFi modem sleep (`wifi:pm start, type: 1`) causes the device to be unreachable for incoming TCP connections and ICMP pings, even though ARP resolves correctly. The radio sleeps between DTIM beacons and misses incoming packets.
- **ATOC must include DEVICE entry (app-device-config.json) for A32 to boot** — The ATOC JSON config MUST include a DEVICE entry referencing app-device-config.json. Without it, the SE processes the ATOC ("ATOC MISC ok") but the A32 cores never start — no clocks, no firewalls, no pin config.
- **WPA supplicant needs 8192+ system workqueue stack** — WPA supplicant operations like `wpa_cli_cmd_disconnect` require significant stack space. CONFIG_SYSTEM_WORKQUEUE_STACK_SIZE=4096 causes stack overflow (USAGE FAULT) when WiFi disconnect runs on the system workqueue. Use 8192 minimum when deferring WiFi operations to k_work on the system workqueue.
- **Alif E7 USB gadget: DWC3 built-in, not modules — no kernel-module RDEPENDS** — The `devkit_e8_defconfig` builds ALL USB support as built-in (`=y`):
