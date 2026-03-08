# JLinkExe Backend for embedded-probe MCP

Status: In-Progress
Created: 2026-02-20
Updated: 2026-03-07

## Problem

probe-rs only supports Cortex-M and RISC-V with known chip definitions. Many targets are unsupported:
- Alif E7 M55_HP (`AE722F80F55D5_HP`) — probe-rs has no chip definition
- Alif E7 A32 (`AE722F80F55D5_A32_0`) — probe-rs has no Cortex-A support at all
- Any vendor-specific target in Segger's device DB but not in probe-rs

Currently we fall back to raw `JLinkExe` via Bash, losing all MCP session management, structured output, and tool integration.

## Approach

Add a JLinkExe subprocess backend alongside probe-rs. Auto-detect: try probe-rs first, fall back to JLinkExe if attach fails. Same MCP tool API — callers don't know which backend is used.

**Why JLinkExe scripting (not GDB server):** Direct halt/reset/read_memory/read_registers without needing a GDB client library. Write command script, run JLinkExe, parse output. Same pattern as existing esptool/nrfutil vendor tools but session-aware.

**Why not probe-rs custom target YAML:** Works for Cortex-M with known memory maps, but can't add Cortex-A support (no architecture enum variant). Also requires reverse-engineering chip definitions that Segger already has.

## Design

### Backend Trait

```rust
// src/backend/mod.rs
pub enum DebugBackend {
    ProbeRs(ProbeRsBackend),
    JLink(JLinkBackend),
}

impl DebugBackend {
    pub async fn halt(&self) -> Result<CoreStatus, DebugError> { ... }
    pub async fn run(&self) -> Result<(), DebugError> { ... }
    pub async fn reset(&self, halt_after: bool, reset_type: &str) -> Result<CoreStatus, DebugError> { ... }
    pub async fn step(&self) -> Result<CoreStatus, DebugError> { ... }
    pub async fn get_status(&self) -> Result<CoreStatus, DebugError> { ... }
    pub async fn read_memory(&self, addr: u64, size: u32) -> Result<Vec<u8>, DebugError> { ... }
    pub async fn write_memory(&self, addr: u64, data: &[u8]) -> Result<(), DebugError> { ... }
    pub async fn read_registers(&self) -> Result<RegisterSet, DebugError> { ... }
    pub async fn write_register(&self, name: &str, value: u64) -> Result<(), DebugError> { ... }
    pub async fn flash_program(&self, path: &str, addr: Option<u64>) -> Result<FlashResult, DebugError> { ... }
    pub async fn flash_erase(&self, full: bool, addr: Option<u64>, size: Option<u32>) -> Result<(), DebugError> { ... }
}
```

### Backend Selection (in `connect()`)

```rust
// Try probe-rs first
match probe_rs_attach(probe_selector, target_chip) {
    Ok(session) => DebugBackend::ProbeRs(session),
    Err(e) if e.is_chip_not_found() => {
        // Fall back to JLinkExe
        if jlink_available() {
            DebugBackend::JLink(JLinkBackend::connect(target_chip, speed_khz)?)
        } else {
            return Err(e) // No fallback available
        }
    }
    Err(e) => return Err(e),
}
```

### JLink Command Execution

```rust
// src/backend/jlink.rs
pub struct JLinkBackend {
    device: String,           // "AE722F80F55D5_HP"
    interface: String,        // "SWD"
    speed_khz: u32,           // 4000
    serial_number: Option<String>,
}

impl JLinkBackend {
    /// Run a JLink command script, return parsed stdout
    async fn execute(&self, commands: &[&str]) -> Result<String, DebugError> {
        let script = tempfile::NamedTempFile::new()?;
        writeln!(script, "si {}", self.interface)?;
        writeln!(script, "speed {}", self.speed_khz)?;
        writeln!(script, "device {}", self.device)?;
        writeln!(script, "connect")?;
        for cmd in commands {
            writeln!(script, "{}", cmd)?;
        }
        writeln!(script, "exit")?;

        let output = Command::new("JLinkExe")
            .args(["-CommandFile", script.path(), "-NoGUI", "1"])
            .output()
            .await?;

        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    }
}
```

### Output Parsers (unit-testable)

```rust
// src/backend/jlink_parser.rs
pub fn parse_registers(output: &str) -> Result<RegisterSet, ParseError> { ... }
pub fn parse_memory_read(output: &str) -> Result<Vec<u8>, ParseError> { ... }
pub fn parse_status(output: &str) -> Result<CoreStatus, ParseError> { ... }
pub fn parse_flash_result(output: &str) -> Result<FlashResult, ParseError> { ... }
```

### JLink Reset Support

Based on verified testing (2026-03-07, 8 tests on Alif E7):

```rust
pub async fn reset(&self, halt_after: bool, reset_type: &str) -> Result<CoreStatus, DebugError> {
    let commands = match reset_type {
        "software" | "aircr" => {
            // AIRCR SYSRESETREQ — core-only reset, does NOT trigger SE reboot
            vec!["w4 0xE000ED0C 0x05FA0004"]
        },
        "hardware" | "nsrst" | "pin" => {
            // NSRST pin — full SoC reset, triggers SE reboot + ATOC processing
            vec!["RSetType 2", "r"]
        },
        _ => {
            // Default: JLink's built-in reset (AIRCR on Alif targets)
            vec!["r"]
        },
    };
    // ...
}
```

## Tool Compatibility

### Phase 1 (MVP — implement now)

| Tool | JLink Support | JLink Commands | Notes |
|------|:---:|---|---|
| `list_probes` | existing | N/A | probe-rs Lister already sees JLink probes |
| `connect` | yes | `si SWD` + `device` + `connect` | Backend auto-detection |
| `disconnect` | yes | No-op (stateless subprocess) | |
| `halt` | yes | `halt` | |
| `run` | yes | `go` | |
| `reset` | yes | `r` or `RSetType 2` + `r` | software vs hardware |
| `step` | yes | `step` or `s` | Single instruction step |
| `get_status` | yes | `halt` + parse PC | |
| `read_memory` | yes | `mem32 <addr>,<count>` | Parse hex table output |
| `write_memory` | yes | `w4 <addr>,<val>` | Word-at-a-time via w4 |
| `read_registers` | yes | `regs` | Parse register dump |
| `write_register` | yes | `wreg <reg>,<val>` | |
| `flash_program` | yes | `loadbin <file>,<addr>` | Binary files. ELF via `loadfile` |
| `flash_erase` | yes | `erase` | Full chip erase |
| `probe_info` | yes | Return session metadata | |

### Phase 2 (defer)

| Tool | Notes |
|------|-------|
| `set_breakpoint` | JLink `setbp` command |
| `clear_breakpoint` | JLink `clrbp` command |
| `set_watchpoint` | JLink watchpoint commands |
| `flash_verify` | JLink `verifybin` command |
| `rtt_attach/read/write` | JLink RTT commands exist but different model |
| `gdb_server` | JLink has `JLinkGDBServerCLExe` |

### Not applicable to JLink backend

| Tool | Reason |
|------|--------|
| `resolve_symbol` | ELF parsing, backend-agnostic (already works) |
| `stack_trace` | Uses symbol table + memory reads (can work with JLink memory reads) |
| `core_dump` | Register + memory dump (can work with JLink) |
| `analyze_coredump` | Post-processing, fully backend-agnostic |
| `load_custom_target` | probe-rs specific |
| `esptool_*` | ESP vendor tool |
| `nrf*` | Nordic vendor tool |

## Implementation Steps

### Step 1: Backend module scaffold
Create `src/backend/mod.rs`, `src/backend/jlink.rs`, `src/backend/jlink_parser.rs`, `src/backend/probe_rs.rs`.

### Step 2: Define DebugBackend enum + dispatch methods
Enum with `ProbeRs` and `JLink` variants. Each method dispatches to the appropriate implementation.

### Step 3: Extract probe-rs code from debugger_tools.rs
Move probe-rs-specific session/core operations into `ProbeRsBackend`. Tools call `backend.read_memory()` instead of `session.core(0).read()`.

### Step 4: Implement JLinkBackend
Subprocess execution, temp file scripts, output parsing.

### Step 5: Implement output parsers with unit tests
`parse_registers()`, `parse_memory_read()`, `parse_status()` — each with comprehensive tests against real JLinkExe output samples.

### Step 6: Update connect() with auto-fallback
Try probe-rs, catch chip-not-found, retry with JLink.

### Step 7: Update DebugSession to hold DebugBackend
Replace `session: Arc<Mutex<probe_rs::Session>>` with `backend: Arc<Mutex<DebugBackend>>`.

### Step 8: Integration test with Alif E7
Verify connect + halt + read_memory + read_registers + reset works via MCP tools.

## Files

| File | Action | Description |
|------|--------|-------------|
| `src/backend/mod.rs` | Create | DebugBackend enum + dispatch methods |
| `src/backend/jlink.rs` | Create | JLinkExe subprocess execution |
| `src/backend/jlink_parser.rs` | Create | Output parsers (unit-testable) |
| `src/backend/probe_rs.rs` | Create | Wrap existing probe-rs code |
| `src/tools/debugger_tools.rs` | Modify | Use backend dispatch instead of direct probe-rs |
| `src/tools/types.rs` | Modify | Add `interface` field to ConnectArgs |
| `src/debugger/mod.rs` | Modify | DebugSession holds DebugBackend |
| `src/lib.rs` | Modify | Add `pub mod backend` |
| `src/error.rs` | Modify | Add JLink error variants |
| `tests/jlink_parser_tests.rs` | Create | Unit tests for output parsing |
| `tests/integration_tests.rs` | Modify | Add JLink backend tests |

## Verification

- [ ] `connect(target_chip="AE722F80F55D5_HP")` auto-falls back to JLink
- [ ] `halt` + `read_registers` returns M55_HP register dump
- [ ] `read_memory(address="0x80002000", size=64)` returns MRAM contents
- [ ] `write_memory` + readback round-trips correctly
- [ ] `reset(reset_type="hardware")` triggers NSRST (full SoC reset)
- [ ] `reset(reset_type="software")` triggers AIRCR (core-only reset)
- [ ] `flash_program` loads binary to target address
- [ ] Existing probe-rs targets (nRF52840, STM32, etc.) still work (no regression)
- [ ] JLinkExe output parsers have unit tests with real output samples
- [ ] Graceful error when JLinkExe not installed
- [ ] `cargo test` passes

## Risks

- **JLinkExe startup latency**: ~200-500ms per invocation. Acceptable for interactive use. Future optimization: persistent process with stdin pipe.
- **Output format instability**: JLinkExe text output is not a stable API. Pin to known patterns, test with captured output samples.
- **JLink license**: J-Link EDU and commercial licenses. Some features may be restricted on EDU probes.
