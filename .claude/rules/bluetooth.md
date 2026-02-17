---
paths: ["**/*ble*.c", "**/*gatt*.c", "**/*prov*.c", "**/bt_gatt*", "**/eai_ble/**", "**/src/zephyr/ble.c", "**/wifi_prov*.c"]
---
# Bluetooth Learnings

- **Defer all heavy operations from BLE GATT callbacks to k_work** — BLE GATT write/read callbacks run on the BLE RX thread with limited stack. Heavy operations (WiFi connect/disconnect, NVS writes, factory reset) MUST be deferred to k_work or k_work_delayable. Running them inline causes stack overflow or BLE connection timeouts. Pattern: callback sets parameters in static struct, then k_work_submit(&work). For boot-time auto-connect, use k_work_schedule(&delayed_work, K_SECONDS(2)) to wait for WiFi driver init.
- **BLE GATT callbacks must not block — use k_work for heavy processing** — BLE GATT write callbacks run in the BLE RX thread. Blocking operations (NVS writes, WiFi connect with semaphore waits, any k_sem_take) will cause the BLE stack to timeout and disconnect the peer. Defer heavy processing to the system workqueue using `k_work_submit()`. Copy callback data to a static buffer before submitting the work item.
- **Zephyr 4.x CCC API change: _bt_gatt_ccc deprecated** — In Zephyr 4.x, the internal CCC (Client Characteristic Configuration) struct `_bt_gatt_ccc` is deprecated. Use `struct bt_gatt_ccc_managed_user_data` instead.
- **CONFIG_BT_DEVICE_NAME_MAX does not exist in Zephyr 4.x** — `CONFIG_BT_DEVICE_NAME_MAX` is not a valid Kconfig option in Zephyr 4.x. Code that uses it for buffer sizing will fail to compile with "undeclared identifier".
- **UUID byte order: Zephyr and NimBLE both use little-endian internally** — Both Zephyr `bt_uuid_128.val[]` and NimBLE `ble_uuid128_t.value[]` store 128-bit UUIDs in little-endian byte order (BLE wire format). Direct memcpy works for both — no byte reversal needed.
