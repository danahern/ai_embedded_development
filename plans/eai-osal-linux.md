# OSAL POSIX/Linux Backend

Status: Complete
Created: 2026-02-16

## Problem

OSAL has Zephyr and FreeRTOS backends, but no Linux/POSIX backend. This means:

1. **All shared library tests require either QEMU or real hardware.** Message encode/decode, state machines, credential logic — none of this needs an RTOS, but we can't run it natively on the dev machine.
2. **No fast iteration loop.** Zephyr twister on QEMU takes 30-60s per test suite. Native Linux execution would be <1s.
3. **No host-based fuzzing or sanitizers.** ASan, MSan, UBSan, and AFL/libFuzzer all work trivially on Linux. Can't use them without a Linux backend.
4. **CI is bottlenecked on QEMU.** GitHub Actions runners are Linux — native tests would be 10-50x faster than QEMU emulation.

This is the highest-leverage improvement for developer experience and test quality.

## Approach

Implement POSIX/pthreads backend for all 9 OSAL primitives. Target both Linux and macOS. Use the ESP-IDF Unity test file as the starting point — port 44 tests to run natively. Build with standalone CMake (no Zephyr/ESP-IDF dependency).

## Solution

POSIX backend implemented with 11 source files in `lib/eai_osal/src/posix/`. All 44 tests pass on macOS with ASan+UBSan clean. Native test infrastructure in `lib/eai_osal/tests/native/` with vendored Unity v2.6.0.

### Primitive Mapping (Final)

| OSAL Primitive | POSIX Implementation | Notes |
|----------------|---------------------|-------|
| Mutex | `pthread_mutex_t` (recursive) | Timed lock via trylock+sleep loop (macOS lacks `pthread_mutex_timedlock`) |
| Semaphore | `pthread_mutex_t` + `pthread_cond_t` + counter | Avoids `sem_init` (deprecated on macOS) |
| Thread | `pthread_create` + condvar for join-with-timeout | Min stack 16KB (POSIX default), priority best-effort |
| Queue | Ring buffer + mutex + 2 condvars | Uses caller-provided buffer (matches Zephyr API contract) |
| Timer | Dedicated thread per timer with condvar wait | Avoids `timer_create` (missing on macOS) |
| Event Flags | `pthread_mutex_t` + `pthread_cond_t` + bitmask | Supports wait_any and wait_all modes |
| Critical Section | Global recursive `pthread_mutex_t` | Lazy-initialized, no IRQ disable on POSIX |
| Time | `clock_gettime(CLOCK_MONOTONIC)` | Ticks = microseconds for precision without overflow |
| Work Queue | Thread + OSAL queue (reuses queue primitive) | System WQ lazy-initialized, delayed work via timer threads |

### Build

```bash
cd lib/eai_osal/tests/native
cmake -B build && cmake --build build
./build/osal_tests                            # 44 tests, <1s
cmake -B build-san -DENABLE_SANITIZERS=ON     # ASan + UBSan
cmake --build build-san && ./build-san/osal_tests
```

### Test Adaptations from ESP-IDF

- `vTaskDelay` → `usleep(ms * 1000)`
- `xSemaphoreCreateBinary/Counting/Give/Take` → OSAL semaphore
- `uxTaskPriorityGet` priority introspection → verify both threads execute (no priority ordering assertion on POSIX)
- `app_main` → `main` with `UNITY_BEGIN/END` + `setUp/tearDown` stubs

## Implementation Notes

### Files Created (16)

| File | Lines | Description |
|------|-------|-------------|
| `src/posix/types.h` | 96 | POSIX type definitions for all 9 primitives |
| `src/posix/internal.h` | 26 | `osal_timespec()` timeout helper using CLOCK_REALTIME |
| `src/posix/mutex.c` | 65 | Recursive mutex, timed lock via trylock+sleep |
| `src/posix/semaphore.c` | 95 | Mutex+condvar counting semaphore |
| `src/posix/thread.c` | 114 | pthread with condvar-based join timeout |
| `src/posix/queue.c` | 122 | Ring buffer with not_full/not_empty condvars |
| `src/posix/timer.c` | 163 | Per-timer thread with condvar-timed wait |
| `src/posix/event.c` | 99 | Mutex+condvar+bitmask with wait_any/wait_all |
| `src/posix/critical.c` | 38 | Global recursive mutex, lazy init |
| `src/posix/time.c` | 33 | CLOCK_MONOTONIC, ticks = microseconds |
| `src/posix/workqueue.c` | 262 | Thread+queue pattern, lazy system WQ, delayed work via timer threads |
| `tests/native/CMakeLists.txt` | 27 | Standalone CMake, optional sanitizers |
| `tests/native/main.c` | 793 | 44 Unity tests ported from ESP-IDF |
| `tests/native/unity/` | 4353 | Vendored Unity v2.6.0 (3 files) |

### Files Modified (1)

| File | Change |
|------|--------|
| `include/eai_osal/types.h` | Added `#elif defined(CONFIG_EAI_OSAL_BACKEND_POSIX)` dispatch branch |

### macOS Compatibility

- `sem_init` deprecated → used mutex+condvar (no sem_t anywhere)
- `timer_create` missing → used dedicated timer threads
- `pthread_mutex_timedlock` missing → used trylock+usleep loop (1ms resolution)
- `pthread_condattr_setclock(CLOCK_MONOTONIC)` unsupported → used CLOCK_REALTIME for condvar timeouts
- `clock_gettime(CLOCK_MONOTONIC)` → available since macOS 10.12+

### Design Decisions

1. **Timer per thread**: Each timer gets its own pthread. Simpler than a timer wheel and acceptable for test-centric usage (not hundreds of timers).
2. **Delayed work via detached threads**: Each `dwork_submit` spawns a short-lived thread that sleeps then enqueues. Previous pending dwork is cancelled before spawning.
3. **Workqueue buffer inline**: `eai_osal_workqueue_t` embeds a 16-slot buffer for the internal queue, avoiding dynamic allocation.
4. **Atomic increments in tests**: Used `__atomic_fetch_add` for shared counters accessed from multiple threads (timer callbacks, work callbacks).

## Modifications

- **Dropped from original ideation**: wifi_prov msg/sm test porting, valgrind CI, libFuzzer targets (deferred to future work)
- **macOS support**: Decided yes — enables local dev without Docker. Required workarounds for 3 missing POSIX APIs.
- **Priority test**: Changed from verifying FreeRTOS priority mapping to verifying both threads execute. POSIX SCHED_OTHER doesn't guarantee priority ordering without root.
