# OSAL Linux Backend

Status: Ideation
Created: 2026-02-16

## Problem

OSAL has Zephyr and FreeRTOS backends, but no Linux/POSIX backend. This means:

1. **All shared library tests require either QEMU or real hardware.** Message encode/decode, state machines, credential logic — none of this needs an RTOS, but we can't run it natively on the dev machine.
2. **No fast iteration loop.** Zephyr twister on QEMU takes 30-60s per test suite. Native Linux execution would be <1s.
3. **No host-based fuzzing or sanitizers.** ASan, MSan, UBSan, and AFL/libFuzzer all work trivially on Linux. Can't use them without a Linux backend.
4. **CI is bottlenecked on QEMU.** GitHub Actions runners are Linux — native tests would be 10-50x faster than QEMU emulation.

This is the highest-leverage improvement for developer experience and test quality.

## Approach

Implement POSIX/pthreads backend for all 9 OSAL primitives. Target: compile shared libraries and their tests as native Linux (or macOS) executables, run directly on the host.

### Primitive Mapping

| OSAL Primitive | POSIX API | Notes |
|----------------|-----------|-------|
| Mutex | `pthread_mutex_t` (recursive) | `PTHREAD_MUTEX_RECURSIVE` attribute |
| Semaphore | `sem_t` (named or unnamed) | macOS deprecated `sem_init` — use dispatch semaphores or named sems |
| Thread | `pthread_create` / `pthread_join` | Priority mapping via `sched_param` (may need root for real-time) |
| Queue | Custom: mutex + condvar + ring buffer | No POSIX equivalent. Same pattern as FreeRTOS implementation. |
| Timer | `timer_create` / `timer_settime` | POSIX per-process timers. macOS: use dispatch timers instead. |
| Event Flags | Custom: mutex + condvar + bitmask | No POSIX equivalent. Straightforward implementation. |
| Critical Section | `pthread_mutex_lock` (global mutex) | No IRQ disable on Linux. Global mutex simulates mutual exclusion. |
| Time | `clock_gettime(CLOCK_MONOTONIC)` | Millisecond resolution is trivial. |
| Work Queue | Custom: thread + queue (reuse queue primitive) | Same design as FreeRTOS backend. |

### macOS Compatibility

macOS (Darwin) is POSIX-compliant but has gaps:
- `sem_init` is deprecated → use GCD dispatch semaphores or named semaphores
- `timer_create` doesn't exist → use `dispatch_source_create` or a timer thread
- `clock_gettime` available since macOS 10.12

Decision needed: target Linux-only, or Linux + macOS? macOS support enables local testing on developer machines without Docker.

### Build System

- **CMake standalone**: `cmake -DEAI_OSAL_BACKEND=linux` — compiles OSAL + test executable
- **No Zephyr or ESP-IDF dependency** — pure CMake + pthreads
- **Unity test framework**: Same test runner pattern as ESP-IDF tests, but runs natively
- Possibly also support building shared libs as native executables with their own test mains

### Test Strategy

1. Port the 44 OSAL tests to run natively (Unity or a lightweight test framework)
2. Port wifi_prov msg/sm tests (no OS dependency — just compile and run)
3. Add sanitizer CI jobs: `gcc -fsanitize=address,undefined`
4. Add valgrind CI job for memory leak detection
5. Stretch: libFuzzer targets for message encode/decode

## Open Questions

- Linux-only or Linux + macOS? (macOS adds complexity but enables local dev)
- Unity as the test framework, or something lighter for host tests (like µnit, Check, or just assert())?
- Should this live in `firmware/` or be a standalone CMake project that can be built outside the Zephyr workspace?
