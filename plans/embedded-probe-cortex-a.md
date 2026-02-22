# Cortex-A32 Support via JLink Backend

Status: Ideation
Created: 2026-02-20

## Problem

probe-rs only supports Cortex-M and RISC-V. The Alif E7 DevKit has Cortex-A32 cores that are debuggable via JLinkExe but not via probe-rs. Attempting `connect(target_chip="Cortex-A32")` fails with "Unable to load specification for chip". We need Cortex-A debug support for the E7 workflow (halt, read registers, read memory, etc.).

## Approach

Add a JLink Commander (JLinkExe) backend to embedded-probe alongside probe-rs. Backend selected automatically based on target chip name. JLink backend shells out to `JLinkExe` via scripted commands (same pattern as esptool/nrfutil vendor tools, but session-aware).

**Why JLinkExe scripting (not GDB server):** JLinkExe provides direct halt/reset/read_memory/read_registers without needing a GDB client library. Simpler: write command script, run JLinkExe, parse output.

**Why not probe-rs custom target YAML:** probe-rs's architecture enum has no Cortex-A variant. Custom target YAML can't add new core architectures — this is a fundamental limitation.

## Design

### Backend Abstraction

```rust
enum DebugBackend {
    ProbeRs(Arc<Mutex<probe_rs::Session>>),
    JLink(JLinkSession),
}

struct JLinkSession {
    device: String,        // "Cortex-A32"
    interface: String,     // "SWD"
    speed_khz: u32,        // 4000
    serial_number: Option<String>,
}
```

### Backend Selection

```rust
fn is_jlink_target(chip: &str) -> bool {
    chip.starts_with("Cortex-A") || chip.starts_with("cortex-a")
}
```

Cortex-A → JLink. Everything else → probe-rs (unchanged).

### JLink Command Execution

Each operation writes a temp script and runs:
```
JLinkExe -device <device> -if SWD -speed <speed> -autoconnect 1 -CommandFile <script>
```
Parse stdout for results. ~200-500ms per invocation.

### Tool Compatibility (Phase 1 MVP)

| Tool | JLink | Notes |
|------|-------|-------|
| `connect` | yes | Backend selection happens here |
| `disconnect` | yes | No-op (stateless) |
| `halt` | yes | `halt` command |
| `run` | yes | `go` command |
| `reset` | yes | `r` command |
| `get_status` | yes | Parse PC, CPSR from `regs` |
| `read_memory` | yes | `mem32 <addr>,<count>` |
| `write_memory` | yes | `w4 <addr>,<val>` |
| `read_registers` | yes | `regs` command, parse output |
| `write_register` | yes | `wreg <reg>,<val>` |

Not supported (defer): breakpoints, watchpoints, RTT, flash_*, core_dump. Cortex-A uses UART not RTT, and E7 MRAM uses SETOOLS not probe-rs flash.

## Files

| File | Change |
|------|--------|
| `src/backend/mod.rs` | **New** — `DebugBackend` enum |
| `src/backend/jlink.rs` | **New** — JLinkExe command execution, output parsing |
| `src/tools/debugger_tools.rs` | Modified — match on backend in each tool |
| `src/tools/types.rs` | Minor — optional `interface` field in ConnectArgs |
| `src/lib.rs` | Add `pub mod backend` |
| `tests/jlink_parsing_tests.rs` | **New** — unit tests for output parsing |

## Verification

- [ ] `connect(target_chip="Cortex-A32")` creates JLink session
- [ ] `halt` + `read_registers` returns A32 register dump
- [ ] `read_memory(address="0x80002000", size=64)` returns MRAM contents
- [ ] Existing Cortex-M targets still use probe-rs (no regression)
- [ ] JLinkExe output parsing has unit tests
- [ ] Error when JLinkExe not installed

## Risks

- **JLinkExe startup latency**: ~200-500ms per operation. Acceptable for interactive debug. Could optimize later with persistent process + stdin pipe.
- **Output format changes**: JLinkExe output is not a stable API. Pin to known patterns, test thoroughly.
