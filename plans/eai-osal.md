# EAI OSAL — Embedded AI OS Abstraction Layer

Status: Complete
Created: 2026-02-15

## Problem

Products need to run on multiple RTOSes (Zephyr, FreeRTOS, Linux) across multiple architectures (ARM Cortex-M/A, RISC-V, Xtensa). Without an OS abstraction layer, every library and application is locked to a single RTOS — duplicating effort and preventing code reuse.

Existing solutions don't fit:
- **CMSIS-RTOS v2**: ARM-only implementations, ARM-specific assumptions (SysTick, PendSV)
- **POSIX**: Too heavyweight for Cortex-M0/32KB targets, incomplete support in Zephyr and FreeRTOS
- **Pigweed**: Requires C++17, opinionated build system
- **NASA OSAL**: No Zephyr or FreeRTOS backends, space-focused

We need a lightweight C abstraction that's architecture-agnostic, supports static allocation for constrained targets, and can serve as the foundation for higher-level portable libraries and frameworks.

## Approach

### Design Principles

1. **Static-first**: All objects statically allocated. No malloc required. Supports M0/32KB floor.
2. **Zero-cost backend selection**: Compile-time backend via CMake/Kconfig. No runtime dispatch, no vtables.
3. **Unified ISR API**: Same functions work from thread and ISR context. Backend handles the difference internally (like Zephyr, unlike FreeRTOS's `_FromISR` split).
4. **Architecture-agnostic**: API has no ARM, RISC-V, or Xtensa assumptions. Backends handle arch-specific details.
5. **Minimal footprint**: Each primitive compiles to thin wrappers around the native OS calls. No abstraction tax beyond a function call.

### API Prefix

`eai_osal_` — e.g., `eai_osal_mutex_lock()`, `eai_osal_thread_create()`, `EAI_OSAL_WAIT_FOREVER`.

Types: `eai_osal_mutex_t`, `eai_osal_thread_t`, `eai_osal_status_t`, etc.

### Backend Architecture

```
eai_osal_mutex_lock()          ← Application code (portable)
       │
       ▼  (compile-time selection)
┌──────────────┬──────────────┬──────────────┐
│   Zephyr     │   FreeRTOS   │    Linux     │
│  k_mutex_*   │ xSemaphore*  │ pthread_*    │
└──────────────┴──────────────┴──────────────┘
```

Types are backend-specific typedefs, not unions or sized buffers. The build system includes the correct backend header, so `eai_osal_mutex_t` maps directly to `struct k_mutex` (Zephyr) or `SemaphoreHandle_t` (FreeRTOS) with zero overhead.

### Phase 1 Primitives

| Category | API Surface |
|----------|------------|
| Thread | create, join, sleep_ms, yield, set_priority, get_current |
| Mutex | create, destroy, lock, unlock, try_lock, timed_lock |
| Semaphore | create (binary + counting), destroy, give, take, try_take, timed_take |
| Message Queue | create, destroy, send, recv, try_send, try_recv, timed variants |
| Timer | create, destroy, start, stop, restart, is_running |
| Event Flags | create, destroy, set, clear, wait (any/all), timed_wait |
| Critical Section | enter, exit (interrupt disable/enable) |
| Time | get_uptime_ms, tick_to_ms, ms_to_tick |

### Status Codes

```c
typedef enum {
    EAI_OSAL_OK = 0,
    EAI_OSAL_ERROR,
    EAI_OSAL_TIMEOUT,
    EAI_OSAL_NO_MEMORY,
    EAI_OSAL_INVALID_PARAM,
    EAI_OSAL_NOT_ALLOWED,      // e.g., blocking call from ISR
    EAI_OSAL_ALREADY_INIT,
    EAI_OSAL_NOT_FOUND,
} eai_osal_status_t;
```

### Time Representation

`uint32_t timeout_ms` for all timeout parameters. Sentinel: `EAI_OSAL_WAIT_FOREVER` (0xFFFFFFFF). `EAI_OSAL_NO_WAIT` (0) for try variants. Simple, fits 32-bit targets, ~49 days max timeout which is sufficient for embedded.

### Directory Structure

```
lib/eai_osal/
├── include/eai_osal/
│   ├── eai_osal.h              # Umbrella include
│   ├── thread.h
│   ├── mutex.h
│   ├── semaphore.h
│   ├── queue.h
│   ├── timer.h
│   ├── event.h
│   ├── critical.h
│   ├── time.h
│   └── types.h                 # Status codes, constants, config
├── src/
│   ├── zephyr/
│   │   ├── thread.c
│   │   ├── mutex.c
│   │   ├── semaphore.c
│   │   ├── queue.c
│   │   ├── timer.c
│   │   ├── event.c
│   │   ├── critical.c
│   │   ├── time.c
│   │   └── types_impl.h        # Zephyr-specific type definitions
│   ├── freertos/
│   │   ├── ...                  # Same file set
│   │   └── types_impl.h        # FreeRTOS-specific type definitions
│   └── linux/
│       ├── ...                  # Same file set
│       └── types_impl.h        # POSIX-specific type definitions
├── Kconfig                      # CONFIG_EAI_OSAL, CONFIG_EAI_OSAL_BACKEND_*
├── CMakeLists.txt
└── tests/
    ├── test_thread.c            # Same tests run on every backend
    ├── test_mutex.c
    ├── test_semaphore.c
    ├── test_queue.c
    ├── test_timer.c
    ├── test_event.c
    └── testcase.yaml            # Twister integration
```

### Build System Integration

- **Zephyr**: Standard Zephyr module with `Kconfig` + `CMakeLists.txt`. Backend selected via `CONFIG_EAI_OSAL_BACKEND_ZEPHYR=y`.
- **FreeRTOS**: CMake with `EAI_OSAL_BACKEND=freertos`. Links against FreeRTOS library.
- **Linux**: CMake with `EAI_OSAL_BACKEND=linux`. Links against pthreads.
- **ESP-IDF**: ESP-IDF uses FreeRTOS internally — use the FreeRTOS backend. May need ESP-IDF-specific Kconfig integration.

### Testing Strategy

One test suite, multiple backends:
- `qemu_cortex_m3` — Zephyr backend (CI, no hardware)
- `qemu_cortex_m3` + FreeRTOS — FreeRTOS backend (if we add FreeRTOS Zephyr integration or standalone QEMU)
- Native Linux — Linux backend (CI, no hardware)
- Hardware boards — validation on real targets

Each primitive gets tests for: basic operation, timeout behavior, ISR context (where applicable), error cases, concurrent access.

### Phase Roadmap

| Phase | Scope | Backends |
|-------|-------|----------|
| 1 | Core primitives (thread, mutex, sem, queue, timer, event, critical) | Zephyr |
| 1.1 | Work queues (work, delayed work, custom queues) | Zephyr |
| 1.5 | FreeRTOS + Linux backends | FreeRTOS, Linux |
| 2 | Memory pools, thread-local storage | All |
| 3 | PAL / Peripheral HAL (GPIO, SPI, I2C, UART) | All |
| 4 | Frameworks on top of OSAL (logging, state machines, etc.) | All |

### Resolved Design Decisions

- **Thread stack allocation**: `EAI_OSAL_THREAD_STACK_DEFINE(name, size)` macro at file scope. Each backend implements to handle alignment (Zephyr's MPU requirements, FreeRTOS's plain buffer, etc.). Attr struct takes stack pointer + size.
- **Priority mapping**: Normalized 0-31 range, higher = higher priority. Each backend maps to native scheme. Matches CMSIS-RTOS2 approach.
- **Recursive mutexes**: All mutexes are recursive by default (matching Zephyr). No separate type. Simplifies API with negligible overhead.

### Open Questions

- **C++ wrapper**: RAII guards (`eai::osal::MutexGuard`), type-safe queues (`eai::osal::Queue<T>`). Phase 1 or Phase 2?

## Solution (Phase 1)

Phase 1 delivered: Zephyr backend for all 8 core primitives with 35 unit tests passing on `qemu_cortex_m3` and hardware validation on nRF54L15 DK via RTT.

Phase 1.1 added work queues: work items, delayed work, and custom work queues with 9 additional tests.

### Deliverables

- **31 new files** in `zephyr-apps/lib/eai_osal/`
- **9 primitives**: mutex, semaphore, thread, queue, timer, event, critical, time, work queue
- **44 tests** across 9 ZTEST suites — 100% pass rate
- **2 modified files**: `lib/CMakeLists.txt`, `lib/Kconfig` (registration)

### API Surface (actual)

Simplified from the ideation plan:
- Thread: `create`, `join`, `sleep`, `yield` (deferred: `set_priority`, `get_current`)
- Mutex: `create`, `destroy`, `lock` (with timeout), `unlock` (try_lock via `NO_WAIT`)
- Semaphore: `create`, `destroy`, `give`, `take` (with timeout)
- Queue: `create`, `destroy`, `send`, `recv` (both with timeout)
- Timer: `create`, `destroy`, `start`, `stop`, `is_running`
- Event: `create`, `destroy`, `set`, `wait` (any/all + timeout), `clear`
- Critical: `enter`, `exit`
- Time: `get_ms`, `get_ticks`, `ticks_to_ms`
- Work: `work_init`, `work_submit`, `work_submit_to`, `dwork_init`, `dwork_submit`, `dwork_submit_to`, `dwork_cancel`, `workqueue_create`

### Key Design Decisions

- **Backend type dispatch**: `include/eai_osal/types.h` uses relative `#include` to pull in `src/zephyr/types.h`. No separate `types_impl.h` — the backend types header IS the impl.
- **No ZEPHYR_EXTRA_MODULES in tests**: The workspace-level `zephyr/module.yml` already routes through `lib/CMakeLists.txt`, so test CMakeLists.txt doesn't need extra module registration.
- **Global include dir**: Uses `zephyr_include_directories_ifdef` (not `zephyr_library_include_directories_ifdef`) so headers are visible to consuming apps.
- **Timer callback trampoline**: Zephyr timer callback takes `struct k_timer*`; OSAL uses `CONTAINER_OF` to recover the `eai_osal_timer_t` and dispatch to the user's `void(void*)` callback.
- **Work/dwork trampolines**: Same `CONTAINER_OF` pattern as timer. Delayed work needs double CONTAINER_OF (k_work → k_work_delayable → eai_osal_dwork_t).
- **Status codes use negative values**: Matches Zephyr errno convention. `EAI_OSAL_OK=0`, errors are negative.
- **Work queues must be static**: `eai_osal_workqueue_t` spawns a persistent thread. Stack-local work queues cause use-after-free when the function returns.

## Implementation Notes

### Files changed
- `lib/CMakeLists.txt` — added `add_subdirectory(eai_osal)`
- `lib/Kconfig` — added `rsource "eai_osal/Kconfig"`
- 29 new files in `lib/eai_osal/`

### Gotchas discovered
- **Workspace module.yml auto-discovery**: `zephyr-apps/zephyr/module.yml` with `cmake: lib` already processes `lib/CMakeLists.txt`. Adding `ZEPHYR_EXTRA_MODULES` in the test causes a binary directory conflict in CMake. Solution: don't use ZEPHYR_EXTRA_MODULES for libraries that are part of the workspace module.
- **Include visibility**: `zephyr_library_include_directories` is library-private. Consumer apps need `zephyr_include_directories` for the headers to be findable.
- **k_msgq_put returns -ENOMSG** (not -EAGAIN) when full with K_NO_WAIT. Added `-ENOMSG` to the timeout mapping in `osal_status()`.

## Modifications

### Deferred from ideation
- `set_priority`, `get_current` thread APIs — not needed for Phase 1 use cases
- `NOT_ALLOWED`, `ALREADY_INIT`, `NOT_FOUND` status codes — YAGNI for Phase 1
- FreeRTOS and Linux backends — Phase 1.5 per roadmap
- Separate test files per primitive — single `main.c` is sufficient for 44 tests

### Hardware validation
- `osal_demo` app deployed to nRF54L15 DK via J-Link
- Producer/consumer pattern: 10/10 messages, mutex-protected stats, event signaling
- Periodic timer heartbeat, critical section, semaphore all confirmed via RTT
- Required `connect_under_reset=true` for initial flash (known RRAM quirk)
