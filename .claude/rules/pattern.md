---
paths: ["**/eai_osal/**", "**/workqueue*"]
---
# Pattern Learnings

- **OSAL work queues must be static — thread outlives stack frame** — `eai_osal_workqueue_create()` (and Zephyr's `k_work_queue_start()`) spawns a persistent thread. If the `eai_osal_workqueue_t` is stack-allocated in a function, the thread continues running after the function returns, referencing freed stack memory. This causes hard faults (typically "ESF could not be retrieved" / fault during interrupt handling).
