---
paths: ["**/sdkconfig.defaults", "**/wifi_prov_wifi_esp*"]
---
# Hardware Learnings

- **ESP32 WiFi power management blocks incoming TCP/ping** — ESP32 WiFi modem sleep (`wifi:pm start, type: 1`) causes the device to be unreachable for incoming TCP connections and ICMP pings, even though ARP resolves correctly. The radio sleeps between DTIM beacons and misses incoming packets.
