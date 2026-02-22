---
paths: ["**/*appkit-e8*", "**/*wifi*.c", "**/alif-e7/**", "**/app-*-config*.json", "**/linux-boot-e7.json", "**/meta-eai/**", "**/prj.conf", "**/sdkconfig.defaults", "**/usb-ecm*.bb", "**/wifi_prov_wifi_esp*"]
---
# Hardware Learnings

- **ESP32 WiFi power management blocks incoming TCP/ping** — ESP32 WiFi modem sleep (`wifi:pm start, type: 1`) causes the device to be unreachable for incoming TCP connections and ICMP pings, even though ARP resolves correctly. The radio sleeps between DTIM beacons and misses incoming packets.
- **Alif E7 UART mapping: ttyS0=UART2 (0x4901a000), ttyS1=UART4 (0x4901c000)** — On the Alif E7 with the appkit-e8 DTB, the Linux serial mapping is:
- **Alif E7 4MB SRAM causes kernel OOM panic — need OSPI RAM or minimal kernel config** — The Alif E7 AppKit has 4MB SRAM (not 8MB as the devkit-e8 DTB originally declared). With the corrected 4MB DTB, Linux boots but immediately panics with OOM:
- **ATOC must include DEVICE entry (app-device-config.json) for A32 to boot** — The ATOC JSON config MUST include a DEVICE entry referencing app-device-config.json. Without it, the SE processes the ATOC ("ATOC MISC ok") but the A32 cores never start — no clocks, no firewalls, no pin config.
- **Alif E7 USB gadget: DWC3 built-in, not modules — no kernel-module RDEPENDS** — The `devkit_e8_defconfig` builds ALL USB support as built-in (`=y`):
- **WPA supplicant needs 8192+ system workqueue stack** — WPA supplicant operations like `wpa_cli_cmd_disconnect` require significant stack space. CONFIG_SYSTEM_WORKQUEUE_STACK_SIZE=4096 causes stack overflow (USAGE FAULT) when WiFi disconnect runs on the system workqueue. Use 8192 minimum when deferring WiFi operations to k_work on the system workqueue.
