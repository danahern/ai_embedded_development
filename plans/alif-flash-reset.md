# Plan: Alif E7 Flash — First-Principles Systematic Validation

**Status:** In-Progress

## Goal

Build a proven, reliable, documented understanding of every step in the Alif E7 flash process. Start from known-good configurations from the official Alif SDK. Introduce ONE new variable at a time. Every claim must be backed by a specific test result.

## Definitions

### Reset Categories

| Category | Method | What it does | How |
|----------|--------|-------------|-----|
| **R1: JTAG/SWD Reset** | JLink `r` command | Debug reset of connected CPU core only. Does NOT reset SE. | `JLinkExe: r` or `reset` MCP command |
| **R2: NSRST (Hardware Reset Pin)** | JLink `SetRESET`/`ClrRESET` or reset button (SW2 on DevKit) | Drives nRESET pin — full SoC reset including SE. SE re-runs boot sequence. | JLink: `SetRESET` + 100ms + `ClrRESET`, or press SW2 |
| **R3: ISP RESET_DEVICE** | ISP command 0x09 sent over SE-UART | Warm reset via SE firmware. Processes STOC. May or may not process ATOC. | `send_cmd(ser, CMD_RESET_DEVICE)` |
| **R4: Cold Power Cycle** | Unplug ALL USB cables | Full power-off/on. SE runs complete boot: SEROM → SES → STOC → ATOC. | Unplug ALL USB (PRG_USB + SOC USB), wait 3s, replug. **NOTE: SOC USB alone keeps board powered — unplugging only PRG_USB is NOT a power cycle.** |

**Hardware-verified behavior (Phase 2 + verification 2026-03-07, 8 tests):**
- **R1a** (JLink default `r` on M55_HP = AIRCR SYSRESETREQ): Resets M55_HP core ONLY. Does NOT trigger SE reboot. Does NOT process ATOC. No FTDI disconnect. (4/4 tests)
- **R1b** (JLink `RSetType 2` + `r` on M55_HP = NSRST pin): Triggers FULL SE reboot. Processes ATOC. ~9 cascading boot sequences (JLink toggles pin ~4 times). No FTDI disconnect. (4/4 tests)
- **R2** (Reset button): Triggers FULL SE reboot. Processes ATOC. Clean single boot.
- **R3** (ISP RESET_DEVICE): Triggers FULL SE reboot. Processes ATOC. Clean single boot.
- **R4** (Cold power cycle): Triggers FULL SE reboot. Processes ATOC. Clean single boot.

**R1b/R2/R3/R4 all process ATOC.** R1a does NOT (core-only reset). R2/R3/R4 are clean single boots. R1b via JLink NSRST causes cascading reboots. FTDI never disconnects during any reset type.

**Power source note:** SOC USB alone keeps the board powered. R1/R2/R3 all work with SOC USB connected (no PRG_USB needed). R4 requires ALL USB cables unplugged — unplugging only PRG_USB while SOC USB is connected does NOT power cycle the board.

### Write Methods

| ID | Method | Tool | Target | Speed |
|----|--------|------|--------|-------|
| **W1** | Official `app-write-mram -p` | Alif binary | MRAM (via SE ISP) | Unknown (dynamic baud) |
| **W2** | MCP `flash()` | Our Python ISP impl | MRAM (via SE ISP) | ~5 KB/s @ 57600 baud |
| **W3** | JLink loadbin | JLinkExe | MRAM (direct) | ~44 KB/s |
| **W4** | JLink FLM | JLinkExe + flash algo | OSPI NOR (direct) | ~6 KB/s |
| **W5** | USB-to-OSPI flasher | M55_HP firmware + XMODEM | OSPI NOR (via SoC) | ~46 KB/s |
| **W6** | Official PC Tool | M55_HE `PC_Tool_HE.bin` + UART2 | OSPI NOR (via SoC) | Unknown |

### ATOC Configs (by complexity, simplest first)

| ID | Name | Images | Known status |
|----|------|--------|-------------|
| **C0** | Official SDK Blinky | DEVICE + M55_HP app | Should work (official example) |
| **C1** | USB flasher | DEVICE + M55_HP flasher | CONFIRMED WORKING |
| **C2** | TFA only | DEVICE + TFA (A32 boot) | CONFIRMED WORKING |
| **C3** | TFA + DTB | DEVICE + TFA + DTB | ROOT CAUSE FOUND: mramAddress < 0x80200000 rejected by SE REV_B4 |
| **C4** | TFA + DTB + M55_HP stub | DEVICE + M55_HP_STUB + TFA + DTB | CONFIRMED FAILING |
| **C5** | Full MRAM boot | DEVICE + TFA + DTB + kernel + rootfs | Unknown |
| **C6** | OSPI boot | DEVICE + M55_HP_STUB + TFA + DTB (OSPI kernel/rootfs) | CONFIRMED FAILING |
| **C7** | Official APSS-OSPI1 | Official Alif reference config | Unknown (need to find config) |

---

## Phase 0: Prerequisites (No Hardware Needed)

### P0.1: Verify Device Config Part Number

Our `app-device-config.json` has `"device": "AE722F80F55D5LS"`. Verify this matches our physical SoC. The AppKit box/PCB silkscreen should show the part number. If it says `AE722F80F55D5BS`, we have a mismatch that would silently prevent all ATOC booting (AUGD0005 p.15).

**Result**: PENDING — requires physical board inspection.

### P0.2: Verify `app-write-mram` Runs ✅

Both tools run:
- `app-write-mram` v1.107.00 — supports `-p` (pad), `-s` (dynamic baud switch, default ON), `-S` (ATOC only), `-nr` (no reset)
- `app-gen-toc` — generates ATOC packages with certificate signing

### P0.3: Locate Official Reference Configs ✅

**SDK configs found** at `docs/alif-e7/AlifSemiconductor.Ensemble.2.1.0/Boards/*/Examples/*/.alif/`:

Official SDK Blinky (`M55_HP_mram_cfg.json`):
```
DEVICE: app-device-config.json [signed]
A32_STUB: a32_stub_0.bin @ loadAddress 0x02000000 [signed, load+boot]
HP_APP: M55_HP_mram_stub.bin @ mramAddress 0x80200000 [UNSIGNED, boot]
HE_STUB: m55_stub_he.bin @ loadAddress 0x58000000 [signed, load+boot]
```

**CRITICAL FINDING — Two different stub binary types:**

| Stub | Size | SP | Reset Vector | Designed For |
|------|------|----|-------------|--------------|
| SDK `M55_HP_mram_stub.bin` | 3040 B | 0x20100000 | 0x80200989 | `mramAddress: 0x80200000` (XIP from MRAM) |
| Our `m55_stub_hp.bin` | 4480 B | 0x20040000 | 0x00000B59 | `loadAddress: 0x50000000` (copy to ITCM) |

These are **completely different binaries** (different MD5, different link addresses). Our stub is for ITCM execution, SDK stub is for MRAM XIP.

**Our setools configs** at `tools/setools/build/config/`:
- `linux-boot-e7-ospi-usbflash.json` (C1, WORKING): DEVICE + M55_HP flasher @ `mramAddress 0x80200000`, unsigned
- `ospi-pass-3-final.json` (C4, FAILING): DEVICE + M55_HP stub @ `loadAddress 0x50000000`, signed + TFA + DTB
- `ospi-pass-3-no-m55.json` (C3): DEVICE + TFA + DTB (no M55)

**Pattern**: All working configs use `mramAddress` + `unsigned`. All failing configs use `loadAddress` + `signed`.

SDK MRAM stub copied to `build/images/m55_mram_stub_hp.bin` for testing.

### P0.4: Inventory All Binaries ✅

| Binary | Size | MD5 | Link Address |
|--------|------|-----|-------------|
| app-device-config.json | 32K | 0228a618... | N/A |
| bl32-ospi.bin | 29K | 944bde35... | 0x80002000 (MRAM) |
| appkit-e7-ospi.dtb | 33K | 074de9ce... | N/A |
| m55_stub_hp.bin (ours) | 4480 B | 0e0e1671... | ITCM 0x50000000 |
| m55_mram_stub_hp.bin (SDK) | 3040 B | 6251e0e1... | MRAM 0x80200000 |
| flasher-hp.bin | 131K | 86f139af... | MRAM 0x80200000 |
| xipImage-ospi | 3.6M | 91cee57a... | 0xC0800000 (OSPI) |
| rootfs-ospi.bin | 4.8M | 1dca9a4e... | 0xC0000000 (OSPI) |
| a32_stub_0.bin | 640 B | c1cbde56... | SRAM 0x02000000 |

### P0.5: Generate ATOC Binaries and Compare Sizes ✅

All sizes are 16-byte aligned.

| Config | ATOC Size | ATOC Address | Entries |
|--------|-----------|--------------|---------|
| C1 (USB flasher) | 4320 | 0x8057EF20 | DEVICE + 1 unsigned (HP flasher) |
| C2 (TFA only) | 4320 | 0x8057EF20 | DEVICE + 1 unsigned (TFA) |
| C3 (TFA+DTB, no M55) | 5232 | 0x8057EB90 | DEVICE + 2 unsigned |
| C4 (TFA+DTB+stub signed) | **12304** | 0x8057CFF0 | DEVICE + 1 **signed** + 2 unsigned |
| C4-mram (TFA+DTB+stub unsigned) | 6144 | 0x8057E800 | DEVICE + 3 unsigned |
| all-stubs | 20784 | 0x8057AED0 | DEVICE + 3 signed |

**Key insight**: A `signed: true` entry adds ~7072 bytes (certificate). An unsigned entry adds ~912 bytes. The size difference is expected, not the cause of failure.

### P0.6: Hex Compare ATOC Headers ✅

First 0x190 bytes are identical across all configs (device certificate block). Image entries start at ~0x1B0. C3 and C4 share the same initial image entry data (TFA/DTB), with C4 having additional M55_HP_STUB entry data.

### P0.7: Test Variant Configs Created

| Config File | Purpose | Key Difference from C4 |
|-------------|---------|----------------------|
| `test-c4-mram-unsigned.json` | Test 4.4 | M55_HP: SDK mram stub, `mramAddress`, unsigned |
| `test-c2-tfa-only.json` | Test 4.1 | TFA only, no M55, no DTB |

### Phase 0 Summary — Top Hypotheses (Updated)

1. **`loadAddress` + `signed: true` is broken** (HIGH confidence): Every working config uses `mramAddress` + `unsigned`. Every failing config uses `loadAddress` + `signed`. The SDK Blinky also uses `mramAddress` + `unsigned` for the actual running M55 firmware. The `loadAddress` + `signed` pattern may require something we're not providing (correct signature key? correct binary format?) or may have a firmware bug in the SE.

2. **Our `m55_stub_hp.bin` is wrong for the config** (MEDIUM): It's linked for ITCM (0x0) but our failing config uses `loadAddress: 0x50000000`. This SHOULD be correct (SE copies to ITCM), but the binary came from an unknown source and differs from the SDK's official stub.

3. **Part number mismatch** (still possible): P0.1 pending — requires physical board inspection.

---

## Phase 1: Establish Baseline with Known-Good Config

### Test 1.1: C1 + W1 + R4 (Known-good via official tool) ✅

**What**: Flash the USB flasher ATOC (C1, known working) using the OFFICIAL `app-write-mram -p` tool, then cold power cycle.

**Prerequisite discovered**: Board had stale factory ATOC at `0x80001ac0` (5 entries, header "OEMTOC01"). Required one-time full MRAM erase via maintenance tool before first successful write.

**Steps**:
1. One-time: Enter maintenance → Fast Erase App MRAM (option 2) + Full Erase (option 1)
2. Generate ATOC: `cd tools/setools && ./app-gen-toc -f build/config/linux-boot-e7-ospi-usbflash.json`
3. Write MRAM: `./app-write-mram -p -b 57600`
4. Cold power cycle (unplug PRG_USB, wait 3s, replug)

**Result**:
- SE-UART: `[SES] ATOC ok`, boot table shows `M55_HP_F | M55-HP | 0x80200000 | u sB` (booted)
- ATOC placed at `0x8057ff90` by app-write-mram (top of application MRAM, growing down)
- USB CDC-ACM: **Did NOT enumerate** — open question, possibly USB PHY config issue
- Pin mux errors for port 15 (non-fatal)
- Flash persistence across R4: **CONFIRMED**

**MRAM layout confirmed**:
- Application MRAM: `0x80000000` to `0x80580000` (5,767,168 bytes)
- ATOC placed at top: header at `0x8057ff90`, entries grow downward
- STOC at `0x80580000` (system MRAM boundary)
- Fast erase clears 16 bytes at `0x8057fff0` (ATOC marker at top of app MRAM)

### Test 1.1b: Overwrite without erase + W1 + R4 ✅

**What**: After 1.1 succeeded, flash a different config (C1) WITHOUT erasing first, to test if erase is always required.

**Result**: **PASS** — ATOC persisted across R4. Overwrite works without erase. The initial erase was a one-time fix for stale factory data.

### Test 1.2: C1 + W2 + R4 (Known-good via MCP)

**What**: Same config (C1) but flash using our MCP instead of official tool.

**Steps**:
1. `gen_toc(config="linux-boot-e7-ospi-usbflash.json")`
2. `flash(config="linux-boot-e7-ospi-usbflash.json", maintenance=true)`
3. Cold power cycle (R4)
4. Check SE-UART for ATOC ok + boot table

**Result**: **PASS**
- SE-UART: `[SES] ATOC ok`, boot table shows `TFA | A32_0 | 0x80002000 | u sB` (booted)
- ATOC written at `0x8057EF20` (4320 bytes), erase pad at `0x8057CF20` (8KB)
- TFA written at `0x80002000` (30144 bytes)
- Total: 42656 bytes in 11.3s (3.7 KB/s)
- Flash persistence across R4: **CONFIRMED**

**Conclusion**: MCP (W2) ISP implementation works correctly. Both W1 and W2 produce persistent writes.

### Test 1.3: C0 + W1 + R4 (Official Blinky via official tool)

**What**: Flash an official Alif SDK Blinky config using official tools. This is the purest baseline.

**Steps**:
1. Copy official `M55_HP_mram_cfg.json` from SDK to our build/config/
2. Copy required binaries (stubs, blinky app) to build/images/
3. `./app-gen-toc -f build/config/M55_HP_mram_cfg.json`
4. `./app-write-mram -p`
5. Cold power cycle (R4)
6. Observe LED activity on board

**Record**:
- SE-UART output: ____
- LED blinks: Yes/No
- JLink M55_HP connection attempt: ____

---

## Phase 2: Reset Category Testing

Use C1 (known working) flashed via W1. Test each reset type.

### Test 2.1: C2 + R1 (JTAG Reset on M55_HP) ✅

Tested with C2 (TFA only) already on board from Test 1.2.

1. JLink connect to M55_HP, send reset
2. Monitor SE-UART

**Result**: **R1 triggers FULL SE reboot** — not core-only as assumed.
- SE-UART shows ~10 rapid full boot sequences (SEROM → SES → ATOC)
- Many partial outputs (SE getting reset mid-boot) before one completes
- Final boot: `[SES] ATOC ok`, TFA booted (`u sB`)
- JLink default reset strategy on M55_HP uses hardware reset (NSRST), making R1 ≈ R2
- **R1 DOES process ATOC** — confirmed

### Test 2.2: C2 + R2 (Reset Button SW2) ✅

1. Pressed reset button
2. Monitored SE-UART

**Result**: **PASS** — Full SE reboot, single clean boot sequence.
- SE-UART: SEROM → SES → `[SES] ATOC ok` → TFA booted (`u sB`)
- No rapid re-reset issues (unlike R1/JLink)
- **R2 DOES process ATOC** — confirmed

### Test 2.3: C2 + R3 (ISP RESET_DEVICE) ✅

1. Opened SE-UART at 57600 via UART MCP
2. Sent raw ISP packets: START_ISP (`03 00 fd`) → ACK, STOP_ISP (`03 01 fc`) → ACK, RESET_DEVICE (`03 09 f4`)
3. Captured boot output

**Result**: **PASS** — Full SE reboot, ATOC processed, TFA booted.
- SE-UART: SEROM → SES → `[SES] ATOC ok` → TFA booted (`u sB`)
- Single clean boot sequence (like R2)
- **R3 DOES process ATOC** — confirmed
- R3 triggers full SE reboot (SEROM → SES → STOC → ATOC), same as R2 and R4

### Test 2.4: R4 (Cold Power Cycle) ✅

Confirmed in Tests 1.1, 1.1b, and 1.2. Full SE reboot, processes ATOC, clean single boot.

### Test 2.5: Verify each reset processes ATOC

After establishing which resets work with C1:
1. Flash C1 via W1 + R4 (known working)
2. Flash C0 (Blinky) via W1 — do NOT power cycle yet
3. Try each reset type (R1, R2, R3, R4)
4. After each: is the board running C0 (Blinky) or still C1 (flasher)?

This determines: which reset types cause the SE to re-read ATOC from MRAM.

| Reset | Board runs C0 (new) or C1 (old)? | Conclusion |
|-------|----------------------------------|------------|
| R1 | | |
| R2 | | |
| R3 | | |
| R4 | | |

---

## Phase 3: Write Method Testing

Use C1 (known working config). Vary ONLY the write method.

### Test 3.1: C1 + W1 + R4 — Already done (Test 1.1)
### Test 3.2: C1 + W2 + R4 — Already done (Test 1.2)

### Test 3.3: C1 + W3 + R4 (JLink loadbin MRAM)

1. Flash C1 via W1 + R4 first (establish known-good ATOC)
2. JLink loadbin the flasher binary to 0x80200000
3. JLink readback — verify data matches
4. Cold power cycle (R4)
5. Does flasher boot? Or did SE overwrite?

**Record**:
- JLink readback matches: Yes/No
- After R4, flasher boots: Yes/No
- JLink readback after R4 matches: Yes/No

**This test answers**: "Does SE restore ATOC-managed MRAM regions from internal storage on every boot?"

### Test 3.4: JLink Write to Non-ATOC MRAM Region

1. C1 already flashed via W1
2. JLink write 0xDEADBEEF to 0x80100000 (no ATOC entry for this address)
3. JLink readback → confirm
4. R4 (cold power cycle)
5. JLink readback → still 0xDEADBEEF?

**This test answers**: "Does SE only restore ATOC-managed regions, or ALL of MRAM?"

### Test 3.5: JLink OSPI Write Persistence

1. C1 flashed (gives us JLink access via M55_HP debug stub)
2. JLink write 16 bytes of 0xAA to 0xC0000000
3. JLink readback → confirm
4. R4 (cold power cycle)
5. JLink readback → still 0xAA?

**This test answers**: "Do J-Link OSPI writes persist across power cycles?"

---

## Phase 4: Incremental ATOC Complexity

Start with simplest working ATOC, add ONE entry at a time. Use ONLY W1 (official tool) + R4 (cold power cycle) to eliminate write method as a variable.

### Test 4.1: C2 (DEVICE + TFA) + W1 + R4 ✅

```json
{
    "DEVICE": { "binary": "app-device-config.json", "version": "0.5.00", "signed": true },
    "TFA": {
        "binary": "bl32-ospi.bin",
        "mramAddress": "0x80002000",
        "cpu_id": "A32_0",
        "flags": ["boot"],
        "signed": false
    }
}
```

Config file: `build/config/test-c2-tfa-only.json`

1. gen_toc + flash (W2 MCP, confirmed equivalent to W1) + R4
2. Monitor SE-UART

**Result**: **PASS**
- SE-UART: `[SES] ATOC ok`, boot table shows `TFA | A32_0 | 0x80002000 | u sB` (booted)
- Confirmed in Tests 1.2, 2.1-2.4
- UART2 not yet connected for TF-A banner verification

### Test 4.2: C3 (DEVICE + TFA + DTB) + W1 + R4 ❌ → ROOT CAUSE FOUND

Config file: `build/config/ospi-pass-3-no-m55.json` (original C3)

**Result**: **FAIL** — `[SES] No ATOC`

**ROOT CAUSE: mramAddress below 0x80200000 is rejected by SE firmware (SES v1.107.0, REV_B4).**

Binary search confirmed exact boundary at **0x80200000 (2MB offset)**:

| mramAddress | ATOC-only | Full flash | cpu_id | flags | Result |
|-------------|-----------|------------|--------|-------|--------|
| 0x8000A000 | yes | - | M55_HP | boot | FAILS |
| 0x80010000 | yes | - | M55_HP | boot | FAILS |
| 0x80010000 | - | yes | (none) | (none) | FAILS |
| 0x80100000 | yes | - | M55_HP | boot | FAILS |
| 0x80180000 | yes | - | M55_HP | boot | FAILS |
| 0x801C0000 | yes | - | M55_HP | boot | FAILS |
| 0x801E0000 | yes | - | M55_HP | boot | FAILS |
| 0x801F0000 | yes | - | M55_HP | boot | FAILS |
| 0x801FF000 | yes | - | M55_HP | boot | FAILS |
| 0x80200000 | yes | - | M55_HP | boot | WORKS |

- NOT a cpu_id issue (tested with and without)
- NOT a flags issue (tested with and without)
- NOT an ATOC-only issue (full flash with binaries also fails at 0x80010000)
- TFA at 0x80002000 is the sole exception (allowed in the reserved region)
- Security Toolkit docs say mramAddress starts from "0x8000-0100 (for REV_Ax)" but don't specify REV_B limit

**Follow-up needed**: Update all production configs to use DTB at 0x80200000+. Also update TF-A build flag `ARM_PRELOADED_DTB_BASE` from 0x80010000 to 0x80200000 and rebuild.

**Diagnostic test 4.2b: 3-entry ATOC without DTB** ✅

Config file: `build/config/test-3entry-no-dtb.json` — DEVICE + M55_HP_STUB + TFA (no DTB)

**Result**: **PASS** — `[SES] ATOC ok`, boot table:
```
M55_HP_S | M55-HP | 0x80200000 | u sB (booted)
TFA | A32_0 | 0x80002000 | u sB (booted)
```

### Test 4.3: C4 (DEVICE + M55_HP_STUB + TFA + DTB) + W1 + R4

**BLOCKED**: Test 4.2 failed — DTB entry itself causes "No ATOC". Must fix DTB entry first before testing M55_HP_STUB + DTB combination.

Original config had M55_HP with `signed: true` + `loadAddress`, but the DTB issue must be resolved first since any config containing a DTB entry fails.

**Pending**: Once DTB fix is found (see Test 4.2 next hypothesis), re-test with M55_HP_STUB + TFA + DTB.

### Test 4.4: C4 variant — M55_HP with `mramAddress` + unsigned (SDK stub)

Same as 4.3, but use the **SDK MRAM stub** with `mramAddress` + `unsigned` (matching SDK Blinky pattern):
```json
    "M55_HP_STUB": {
        "binary": "m55_mram_stub_hp.bin",
        "mramAddress": "0x80200000",
        "cpu_id": "M55_HP",
        "flags": ["boot"],
        "signed": false
    }
```

**Config file**: `build/config/test-c4-mram-unsigned.json` (pre-generated, ATOC = 6144 bytes)

**IMPORTANT**: Uses SDK's `M55_HP_mram_stub.bin` (3040 B, linked for 0x80200000), NOT our `m55_stub_hp.bin` (4480 B, linked for ITCM). The binary MUST match the address type.

**Record**: ____

### Test 4.4b: C4 variant — `loadAddress` + `unsigned` (isolates signed vs loadAddress)

Same as 4.3, but with `signed: false`:
```json
    "M55_HP_STUB": {
        "binary": "m55_stub_hp.bin",
        "loadAddress": "0x50000000",
        "cpu_id": "M55_HP",
        "flags": ["load", "boot"],
        "signed": false
    }
```

**Config file**: `build/config/test-c4-load-unsigned.json` (pre-generated, ATOC = 10624 bytes)

Uses our `m55_stub_hp.bin` (4480 B, linked for ITCM at 0x0), which IS correct for `loadAddress: 0x50000000`.

**Record**: ____

### 2×2 Decision Matrix (Tests 4.3, 4.4, 4.4b)

| Test | Address Type | Signed | Binary | ATOC Size | Expected |
|------|-------------|--------|--------|-----------|----------|
| 4.3 | loadAddress 0x50000000 | **true** | m55_stub_hp.bin (ITCM) | 12304 | FAIL |
| 4.4 | mramAddress 0x80200000 | false | m55_mram_stub_hp.bin (MRAM) | 6144 | PASS |
| 4.4b | loadAddress 0x50000000 | **false** | m55_stub_hp.bin (ITCM) | 10624 | ? |

**Interpretation:**
- 4.3 FAIL + 4.4 PASS + 4.4b PASS → `signed: true` is the sole problem
- 4.3 FAIL + 4.4 PASS + 4.4b FAIL → `loadAddress` mechanism or our stub binary is broken
- 4.3 FAIL + 4.4 FAIL → Problem is not M55_HP specific (something else wrong)

### Test 4.5: C5 (Full MRAM boot) + W1 + R4

```json
{
    "DEVICE": { ... },
    "TFA": { "binary": "bl32.bin", "mramAddress": "0x80002000", "cpu_id": "A32_0", "flags": ["boot"], "signed": false },
    "DTB": { "binary": "appkit-e7.dtb", "mramAddress": "0x80010000", "signed": false },
    "KERNEL": { "binary": "xipImage", "mramAddress": "0x80020000", "signed": false },
    "ROOTFS": { "binary": "alif-tiny-image-appkit-e7.cramfs-xip", "mramAddress": "0x80380000", "signed": false }
}
```

1. gen_toc + app-write-mram -p + R4 (NOTE: this will be slow, ~5MB of images)
2. Monitor UART2 — full Linux boot expected

**Record**: ____

### Test 4.6: W1 vs W2 Comparison

For whichever config first fails in 4.1-4.5, retry with W2 (our MCP). If the official tool works but our MCP doesn't, we know the MCP has a bug.

For whichever config first succeeds with W1 but previously failed, this isolates the exact difference.

---

## Phase 5: OSPI Programming

Only proceed after Phase 4 has a working Linux MRAM boot.

### Test 5.1: USB-to-OSPI Flasher + Normal Boot ATOC ✅

1. Flash C1 (flasher) via JLink ATOC bootstrap + ISP — flasher boots
2. Send combined OSPI image via XMODEM (W5) — 12.1MB in 256s (46.3 KB/s)
3. Flash C3 (TFA+DTB boot ATOC) via JLink ATOC w4 + NSRST in same session
4. Monitor UART2 — Linux boots from OSPI

**Result**: **PASS** — Linux boots from OSPI!
- OSPI programming: 12.1MB combined image (rootfs 8MB + kernel 3.7MB) via USB CDC-ACM XMODEM at 46.3 KB/s
- Flasher CDC-ACM port: `/dev/cu.usbmodem12001` (VID 0x0525, PID 0xa4a7, serial "1200") on SOC USB
- SE-UART: `[SES] ATOC ok`, TFA booted (`u sB`), DTB loaded (`u s`)
- UART2: Full TF-A banner + Linux boot from OSPI XIP
  - `OSPI Version = 3130332a`, `Configured OSPI NOR Flash successfully`
  - `Linux version 6.12.6-yocto-standard` booting from `root=mtd:physmap-flash.0`
  - `cramfs: linear cramfs image on mtd:physmap-flash.0 appears to be 4932 KB in size`
  - Rootfs mounted successfully (cramfs, read-only)
  - `Warning: unable to open an initial console.` — console issue, not flash-related

**ATOC persistence across JLink sessions (corrected 2026-03-07):**
- JLink's MRAM flash algorithm (Bank 0 @ 0x80000000) preserves w4 writes on session disconnect
- ATOC data survives across multiple JLink sessions — verified with test patterns and real ATOC
- The "ATOC zeros after reset" seen earlier was caused by the SE clearing ATOC after processing (by design), not by JLink
- Multi-session workflow works: write ATOC in session 1, load binaries + reset in session 2
- `loadbin` implicit resets do NOT clear ATOC (verified by mem32 read after loadbin)

**Flasher SE hang issue:**
- Flasher firmware calls `SERVICES_set_run_cfg(USB_PHY_MASK)` which hangs the SE
- With SE hung: ISP unresponsive, JLink can't find M55_HE (AP[4]), can't halt M55_HP
- Recovery requires: hard maintenance mode (native Alif tool) + full MRAM erase, then re-flash
- JLink NSRST alone is insufficient — USB PHY hardware state persists across soft reset

**JLink DTB format rejection:**
- JLink `loadbin` rejects `.dtb` files: "File is of unknown / unsupported format" (DTB magic 0xD00DFEED confuses format detection)
- **Workaround**: Copy DTB to `.bin` extension: `cp foo.dtb /tmp/dtb_raw.bin && loadbin /tmp/dtb_raw.bin 0x80200000`

### Test 5.2: JLink OSPI + Normal Boot ATOC

1. Flash C6 (OSPI boot ATOC) via W1 + R4
2. JLink write kernel to 0xC0800000 (W4)
3. JLink write rootfs to 0xC0000000 (W4)
4. R4 (cold power cycle)
5. Monitor UART2 — Linux boots?

**Record**: ____

### Test 5.3: Official PC Tool (if available)

1. Flash PC Tool burner ATOC via W1 + R4
2. Run flashtool GUI (W6)
3. Flash kernel + rootfs to OSPI
4. Flash C6 via W1 + R4
5. Monitor UART2

**Record**: ____

---

## CRITICAL FINDING: MCP Bypasses `app-write-mram`

Our `alif-flash` MCP does NOT call `app-write-mram`. It implements its own ISP protocol:

1. Calls `app-gen-toc` to produce `AppTocPackage.bin` (correct)
2. Calculates ATOC address: `system_mram_base (0x80580000) - atoc_size`
3. Writes an 8KB zero-pad below the ATOC to erase stale magic bytes
4. Writes AppTocPackage.bin via BURN_MRAM ISP command
5. Writes each image binary to its mramAddress via BURN_MRAM
6. Sends STOP_ISP + RESET_DEVICE (warm reset — may NOT process ATOC!)

**`app-write-mram` flags (from `--help`):**
```
-p, --pad           pad the binary if size is not multiple of 16
-s, --switch        dynamic baud rate switch toggle, default=on
-S, --skip          write ATOC only - skip user managed images
-nr, --no_reset     do not reset target before operation
-a, --auth_image    authenticate the image by sending its signature file
```

**Differences from official `app-write-mram -p`:**
1. **Dynamic baud rate switch** — official tool defaults to switching from 57600 to 921600 during writes (`-s` is ON by default). Our MCP stays at 57600.
2. **RESET_DEVICE at the end** — instead of the reset that `app-write-mram` performs.
3. **Custom zero-erase-pad** — our 8KB erase pad to clear stale ATOC is our invention, not official.
4. **Unknown ATOC address logic** — we calculate `system_mram_base - atoc_size`. Does `app-write-mram` do the same?

Note: Our MCP DOES pad individual images to 16-byte boundaries (verified in source). ATOC package sizes from `app-gen-toc` are already 16-byte aligned (12304 = 769×16, 4320 = 270×16). So padding is NOT the differentiator.

## Key Hypotheses (Ranked by Likelihood, Updated After ISP ATOC Failure Investigation)

1. **RESOLVED: mramAddress < 0x80200000 rejected by SE REV_B4** (CONFIRMED):
   - Root cause of ALL "No ATOC" failures with DTB entries
   - Binary search confirmed exact boundary at 0x80200000 (2MB offset from MRAM base)
   - Independent of cpu_id, flags, signed status, or whether binaries are present
   - TFA at 0x80002000 is the sole exception (trusted firmware entry point)
   - Security Toolkit docs only specify REV_Ax minimum (0x80000100), silent on REV_B
   - **Fix**: Move DTB to 0x80200000+, rebuild TF-A with `ARM_PRELOADED_DTB_BASE=0x80200000`
   - **Fix applied and verified**: TF-A rebuilt, DTB at 0x80200000 boots successfully

2. **ISP ATOC write silently fails after `-e APP` erase** (CONFIRMED, root cause unknown):
   - Both W1 and W2 silently drop ISP writes to ATOC area (~0x8057xxxx)
   - Lower addresses (TFA, DTB) write correctly via ISP
   - JLink writes to ATOC area work fine
   - NOT caused by firewall configuration (tested with DEVICE config loaded)
   - May be caused by: (a) `-e APP` leaving bad state, (b) Phase 4 corrupt writes damaging system MRAM, or (c) maintenance menu erase vs command-line erase difference
   - **Workaround**: JLink ATOC bootstrap

3. **`signed: true` on M55_HP entry may also block boot** (MEDIUM — not yet isolated):
   - Cannot test independently until configs are updated with correct addresses
   - Every WORKING config: `unsigned`
   - `signed: true` generates certificates — SE verification may fail with dev keys

4. **MCP ISP protocol difference** (DISPROVEN):
   - W2 (MCP) confirmed equivalent to W1 for working configs (C1, C2)
   - Also confirmed: both W1 and W2 fail identically for ATOC writes

5. **C3 state corruption** (CONFIRMED — operational hazard):
   - Writing a config with addresses < 0x80200000 corrupts state
   - Requires MRAM erase before re-testing
   - **Always erase before writing after a failed config**

## CRITICAL FINDING: ISP ATOC Write Silent Failure (Post Full Erase)

**Discovered during Phase 5 prep (2026-03-07).**

After a full MRAM erase (`app-write-mram -e APP`), ISP BURN_MRAM writes to the ATOC area (~0x8057xxxx) are **silently dropped**. Both W1 (native `app-write-mram -p`) and W2 (MCP `flash()`) exhibit identical behavior:
- SE ACKs all commands (BURN_MRAM, DOWNLOAD_DATA, DOWNLOAD_DONE) — no errors
- JLink readback shows all zeros at the ATOC address
- Lower MRAM writes (TFA @ 0x80002000, DTB @ 0x80200000) persist normally

**Firewall hypothesis disproven**: Loading DEVICE config with open firewalls (by writing ATOC via JLink first, power cycling to process it) does NOT fix ISP writes to the ATOC area. The SE drops ATOC ISP writes regardless of DEVICE config state.

**JLink workaround confirmed**: JLink loadbin to the ATOC area works, and SE processes it correctly (`[SES] ATOC ok`).

**Open question**: During Phase 1, ISP ATOC writes DID work (Tests 1.1, 1.1b, 1.2). The difference:
- Phase 1 erase: SE maintenance menu (Fast Erase option 2 + Full Erase option 1)
- Phase 4 erase: `app-write-mram -e APP` command
- These may clear different regions or set different SE state flags
- Phase 4 binary search may have also corrupted system MRAM state

**Hypothesis**: The `-e APP` erase or the Phase 4 corrupt-address writes left residual state in system MRAM that blocks ISP writes to the ATOC area. The maintenance menu erase may properly clear this state. Needs testing.

**Current workaround**: Use JLink to write the ATOC package, then ISP for user images (TFA, DTB).

### Test: DTB at 0x80200000 via JLink Bootstrap ✅

1. Rebuilt TF-A with `ARM_PRELOADED_DTB_BASE=0x80200000` (30140 bytes)
2. JLink loadbin: TFA→0x80002000, DTB→0x80200000, ATOC→0x8057EB90
3. Power cycle
4. SE-UART: `[SES] ATOC ok`, boot table shows TFA booted on A32_0, DTB loaded

**Confirmed**: DTB at 0x80200000 is accepted by SE. TF-A builds correctly with new DTB base.

## Follow-Up Actions (Post Phase 4)

- [x] Rebuild TF-A with `ARM_PRELOADED_DTB_BASE=0x80200000` — done (30140 bytes)
- [ ] Update all production configs: DTB from 0x80010000 → 0x80200000
- [ ] Update all production configs: OSPI header from 0x8000E000 → 0x80200000+
- [ ] Update all production configs: kernel from 0x80020000 → 0x80210000+ (if in MRAM)
- [ ] Update `RAM_PRELOADED_DTB_BASE` if needed
- [ ] Test updated configs end-to-end (full Linux boot)
- [ ] Investigate maintenance menu erase vs `-e APP` erase for ISP ATOC write recovery
- [ ] Add JLink ATOC bootstrap to MCP flash tool as fallback
- [x] ~~Fix JLink ATOC clearing on connect~~ — RESOLVED: JLink does NOT clear ATOC. SE clears it after processing (by design). ATOC persists across JLink sessions.
- [ ] Fix console issue: `Warning: unable to open an initial console.` in OSPI boot (rootfs missing /dev/console?)
- [ ] Test OSPI persistence across power cycle (OSPI data written, but not yet verified post-R4)
- [ ] Automate OSPI flash workflow: flasher ATOC → XMODEM → boot ATOC → boot (currently manual)

## Verification Output Format

For each test, create a knowledge item ONLY if the result is conclusive and reproducible. Format:

```
Test ID: X.Y
Config: CZ
Write Method: WN
Reset: RN
Result: PASS / FAIL
Evidence: [exact SE-UART output, UART2 output, JLink readback]
Conclusion: [one sentence]
```

Do NOT capture knowledge from a single test run. Reproduce at least once before capturing.

## Documentation Outputs

After all tests complete:
1. **Proven flash workflow** — step-by-step commands with exact timing
2. **Reset behavior matrix** — which resets process ATOC, which don't
3. **Write method matrix** — which methods produce persistent writes
4. **ATOC config guide** — which fields are required, which flags matter
5. **Updated CLAUDE.md / rules** — based on proven results only
6. **Knowledge items** — one per proven fact, severity=critical, status=validated

## Files

| File | Action |
|------|--------|
| `plans/alif-flash-reset.md` | This plan |
| `.claude/rules/alif-common.md` | Cleaned — removed unverified claims |
| `.claude/rules/alif-e7-hardware.md` | Cleaned — doc-sourced facts only |
| `claude-mcps/alif-flash/CLAUDE.md` | Cleaned — removed method recommendations |
| `MEMORY.md` | Cleaned — removed flash state, marked reset in progress |
| Knowledge items (31) | Deprecated — all flashing-related items |
| `plans/usb-ospi-flasher.md` | Superseded by this plan |
