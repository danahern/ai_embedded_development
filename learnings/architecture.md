# Learnings: Architecture Decisions

### Two coredump strategies
- **RTT-only** (`debug_coredump.conf`): Simple, no flash partition needed. Data streams through RTT at crash time. Lost if no one is reading.
- **Flash-backed** (`debug_coredump_flash.conf`): Persists to flash, survives reboot. `crash_log` module re-emits on next boot. Needs a DTS overlay with `coredump_partition`.

### Zephyr coredump captures exception frame registers
The coredump subsystem captures PC/LR/SP from the ARM exception frame — the actual crash site. This is better than halting after a fault and reading registers, which only shows the fault handler context.
