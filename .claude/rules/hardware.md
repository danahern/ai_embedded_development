---
paths: ["**/*appkit-e7*.dts", "**/*appkit-e8*", "**/alif-e7/**", "**/platform_def.h", "**/sdkconfig.defaults", "**/wifi_prov_wifi_esp*", "claude-mcps/alif-flash/**/server.py"]
---
# Hardware Learnings

- **ESP32 WiFi power management blocks incoming TCP/ping** — Modem sleep (`type: 1`) makes device unreachable for incoming connections. Radio sleeps between DTIM beacons. Fix: disable power save or use `esp_wifi_set_ps(WIFI_PS_NONE)`.
- **Alif E7 UART mapping: ttyS0=UART2 (0x4901a000), ttyS1=UART4 (0x4901c000)** — Console is on UART2/ttyS0 (earlycon and main console). J15 jumpers select which UART routes to JLink VCOM. Use UART2 position for console output.
- **Alif E7 UART peripheral clock is 100 MHz (dwuartclk), not 20 MHz** — Confirmed by register reads, datasheet, and divisor calculations. The DTS `clock-frequency` property must be 100000000 for correct baud rate generation.
- **Alif E7 AppKit: Fixed dual-serial setup — no jumper switching needed** — Use two FTDI cables: `/dev/cu.usbserial-A10LOVM2` (SE-UART for ISP/flashing) and `/dev/cu.usbserial-AO009AHE` (UART2 for Linux console). No J15 jumper changes required.
