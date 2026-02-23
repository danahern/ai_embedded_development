---
paths: ["**/*appkit-e7*.dts", "**/*appkit-e8*", "**/alif-e7/**", "**/platform_def.h", "**/sdkconfig.defaults", "**/wifi_prov_wifi_esp*", "claude-mcps/alif-flash/**/server.py"]
---
# Hardware Learnings

- **ESP32 WiFi power management blocks incoming TCP/ping** — ESP32 WiFi modem sleep (`wifi:pm start, type: 1`) causes the device to be unreachable for incoming TCP connections and ICMP pings, even though ARP resolves correctly. The radio sleeps between DTIM beacons and misses incoming packets.
- **Alif E7 UART peripheral clock is 100 MHz (dwuartclk), not 20 MHz** — The Alif E7 UART peripheral clock (dwuartclk / baudclk) is **100 MHz**, confirmed by three independent sources:
- **Alif E7 UART mapping: ttyS0=UART2 (0x4901a000), ttyS1=UART4 (0x4901c000)** — On the Alif E7 with the appkit-e8 DTB, the Linux serial mapping is:
- **Alif E7 AppKit: Fixed dual-serial setup — no jumper switching needed** — The Alif E7 AppKit can run with a **fixed serial setup** that eliminates J15 jumper switching:
