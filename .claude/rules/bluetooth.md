---
paths: ['**/*ble*.c', '**/*gatt*.c', '**/*prov*.c', '**/wifi_prov*.c']
---
# Bluetooth Learnings

- **BLE GATT callbacks must not block — use k_work for heavy processing** — BLE GATT write callbacks run in the BLE RX thread. Blocking operations (NVS writes, WiFi connect with semaphore waits, any k_sem_take) will cause the BLE stack to timeout and disconnect the peer. Defer heavy processing to the system workqueue using `k_work_submit()`. Copy callback data to a static buffer before submitting the work item.
- **Defer all heavy operations from BLE GATT callbacks to k_work** — BLE GATT write/read callbacks run on the BLE RX thread with limited stack. Heavy operations (WiFi connect/disconnect, NVS writes, factory reset) MUST be deferred to k_work or k_work_delayable. Running them inline causes stack overflow or BLE connection timeouts. Pattern: callback sets parameters in static struct, then k_work_submit(&work). For boot-time auto-connect, use k_work_schedule(&delayed_work, K_SECONDS(2)) to wait for WiFi driver init.
