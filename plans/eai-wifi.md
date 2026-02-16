# eai_wifi — Portable WiFi Connection Manager

Status: Ideation
Created: 2026-02-16

## Problem

WiFi scan/connect was the second most expensive rewrite in the ESP-IDF port:
- `wifi_prov_wifi.c` (~254 lines) — Zephyr `net_mgmt` (`NET_REQUEST_WIFI_SCAN`, `NET_REQUEST_WIFI_CONNECT`)
- `wifi_prov_wifi_esp.c` (~230 lines) — ESP-IDF `esp_wifi` (`esp_wifi_scan_start`, `esp_wifi_connect`)

The APIs differ significantly:
- **Scan results:** Zephyr delivers per-result callbacks. ESP-IDF delivers a batch after scan completes.
- **Connect semantics:** Zephyr fires `NET_EVENT_WIFI_CONNECT_RESULT`. ESP-IDF fires `WIFI_EVENT_STA_DISCONNECTED` for both auth failure and real disconnect.
- **IP acquisition:** Zephyr uses `net_dhcpv4_start()` explicitly. ESP-IDF's `esp_netif` handles DHCP automatically.
- **Power management:** ESP-IDF enables modem sleep by default (breaks incoming TCP). Zephyr doesn't.

## Approach

Abstract at the connection manager level — scan, connect, disconnect, get status.

### Candidate API Surface

```c
#include <eai_wifi/eai_wifi.h>

int eai_wifi_init(void);

/* Scan */
typedef void (*eai_wifi_scan_result_cb_t)(const struct eai_wifi_scan_result *result);
typedef void (*eai_wifi_scan_done_cb_t)(int status);
int eai_wifi_scan(eai_wifi_scan_result_cb_t on_result, eai_wifi_scan_done_cb_t on_done);

/* Connect / disconnect */
typedef void (*eai_wifi_event_cb_t)(enum eai_wifi_event event);
int eai_wifi_connect(const char *ssid, const char *psk, enum eai_wifi_security sec);
int eai_wifi_disconnect(void);
void eai_wifi_set_event_callback(eai_wifi_event_cb_t cb);

/* Status */
enum eai_wifi_state eai_wifi_get_state(void);
int eai_wifi_get_ip(uint8_t ip[4]);
```

### Key Design Decisions

- **Unified scan result delivery.** Backend normalizes: Zephyr calls `on_result` per AP then `on_done`. ESP-IDF collects batch then calls `on_result` per AP then `on_done`. Consumer sees the same sequence.
- **Clear event semantics.** `EAI_WIFI_EVT_CONNECTED`, `EAI_WIFI_EVT_DISCONNECTED`, `EAI_WIFI_EVT_CONNECT_FAILED` — backend maps platform events to these. No ambiguous "disconnected means maybe auth failure" leaking through.
- **DHCP handled internally.** `eai_wifi_connect()` starts DHCP. `EAI_WIFI_EVT_CONNECTED` fires only after IP is acquired.
- **Power management handled internally.** Backend disables modem sleep on ESP-IDF. Zephyr doesn't need it.

### Challenges

- **Scan result memory.** Zephyr callback gives a pointer that's valid only during the callback. ESP-IDF gives an array that must be freed. Abstraction needs clear ownership semantics.
- **Enterprise WiFi.** WPA2-Enterprise with certificates is significantly different across platforms. Out of scope for v1.
- **Linux backend.** `wpa_supplicant` D-Bus API or NetworkManager. Very different from embedded WiFi stacks. Deferred.

### Scope (v1)

- WiFi STA mode only (no AP/SoftAP)
- Open, WPA-PSK, WPA2-PSK, WPA3-SAE security types
- Scan, connect, disconnect, get IP
- Backends: Zephyr net_mgmt, ESP-IDF esp_wifi
- No enterprise WiFi, no AP mode, no Linux backend in v1
