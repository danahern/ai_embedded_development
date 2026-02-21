# Retrospective: Alif E7 First Linux Boot

Date: 2026-02-20
Duration: ~4 sessions across 3 days
Result: Linux kernel running on Alif Ensemble E7 AI/ML AppKit (AK-E7-AIML)

## What We Did

Brought up Linux on the Alif Ensemble E7 SoC for the first time. The E7 is a complex multi-core SoC (dual Cortex-A32 + dual Cortex-M55 + Ethos-U55 NPU) where all boot and flash operations go through a Cortex-M0+ Secure Enclave (SE) using Alif's proprietary SETOOLS. No Linux BSP documentation existed for our specific board (AK-E7-AIML AppKit).

## Timeline

### Session 1: Tooling Setup + First Flash
- Installed SETOOLS, figured out the ATOC JSON schema from SETOOLS User Guide
- Generated ATOC with memory map from Yocto machine config (devkit-e8.conf)
- Flashed all images via `app-write-mram`
- A32 stuck at data abort in TF-A — PC=0x800050EC

### Session 2: TF-A Patches
- Root-caused TF-A abort to two register writes that don't exist on E7:
  1. PERIPH_CLK_ENA OSPI clock write
  2. NPU-HG initialization
- Patched TF-A in Yocto, rebuilt, reflashed via custom ISP script
- Kernel started but immediately crashed

### Session 3: DTB Memory Bug + Bricking
- Root-caused kernel crash: DTB declares 8MB SRAM, hardware has 4MB
- Kernel allocates page tables in non-existent SRAM, double faults
- FC5 firewall exception flood drowns SE-UART, blocking ISP
- Board effectively "bricked" — can't flash, can't debug
- Binary patched DTB on disk (offset 560: 0x007de000 → 0x00400000)
- Multiple recovery scripts attempted (isp_precision, isp_recover, isp_aggressive)
- **Lesson learned**: stop automating when you're going in circles

### Session 4: Recovery + First Boot (This Session)
- User manually entered maintenance mode (maintenance tool + physical RESET)
- Erased MRAM, wrote ATOC + images via `app-write-mram -nr` + custom `isp_write_all.py`
- Board reset — SE-UART quiet (no firewall flood!), but no Linux console output
- Discovered: UART4 console (ttyS0) needs J15 jumpers on AppKit
- **Key breakthrough**: Flashed Alif's `app-cpu-stubs.json` (factory test) — A32 booted!
  - Stubs include `DEVICE` entry (app-device-config.json) — our Linux config was missing it
  - Without DEVICE config: no clocks, no firewalls, A32 never starts
- Added DEVICE entry to `linux-boot-e7.json`, regenerated ATOC
- Discovered programmatic maintenance mode (START_ISP → SET_MAINTENANCE → STOP_ISP → RESET)
- Full flash via `app-write-mram -v -p -b 57600` in maintenance mode
- **JLink SWD confirmed: Linux kernel running at EL1, Non-secure, IRQs enabled, PC in 0xBFxxxxxx**

## What Went Well

1. **Systematic debugging via JLink SWD**: Reading A32 registers and MRAM at each stage was invaluable. Comparing stubs (PC=0x02000260, EL3, Secure) vs Linux (PC=0xBFxxxxxx, EL1, Non-secure) gave definitive proof.

2. **Using factory test configs as baseline**: Flashing `app-cpu-stubs.json` isolated the problem to our config (missing DEVICE entry) vs hardware. This was the key insight.

3. **Custom ISP scripts**: When `app-write-mram` refused to cooperate (GET_REVISION failure), custom Python scripts (`isp_write_all.py`, `isp_direct_write.py`) kept progress moving.

4. **Saleae for signal-level debugging**: Confirmed which pins had activity and which were idle, validated baud rates, caught the SE spinner pattern.

5. **Knowledge capture**: Each session captured learnings. The knowledge items from sessions 1-3 directly informed session 4's approach.

## What Went Wrong

1. **Missing DEVICE config was the #1 time sink**. The ATOC JSON needs a DEVICE entry pointing to `app-device-config.json` (firewalls, clocks, pinmux). Without it, the SE processes the ATOC but never configures the hardware for A32 boot. This wasn't documented anywhere we found — we only discovered it by comparing the working stubs config to our config.

2. **Wrong device selection (E8 vs E7)** caused baud rate mismatches. The E7 tools-config says 55000 baud but the SE actually runs at 57600. This caused hours of garbled GET_REVISION responses and "Malformed packet" errors.

3. **Automated recovery attempts were counterproductive in Session 3**. Multiple scripts (isp_precision, isp_recover, isp_aggressive) tried to catch the ISP window during reset — none worked because the firewall flood was too fast. Should have gone to manual recovery (maintenance tool + physical button) immediately.

4. **DTB binary patch instead of source fix**. Patching the DTB binary at a hardcoded offset works but is fragile. Should fix in the Yocto DTS source so rebuilds produce the correct DTB automatically.

5. **No serial console visibility yet**. The kernel is running but we can't see its output. The UART4 console needs J15 jumpers or device config pinmux changes. This should have been investigated earlier.

## Key Technical Learnings

| Learning | Impact |
|----------|--------|
| ATOC must include DEVICE entry | **Critical** — without it, nothing boots |
| SE-UART baud is 57600, not 55000 | **Critical** — wrong baud = garbled responses |
| Programmatic maintenance mode via ISP commands | **Critical** — no physical button needed |
| `app-write-mram` needs maintenance mode for full write | **Important** — `-nr` is ATOC-only |
| `-p` flag required for non-aligned images | **Important** — silent exit without it |
| MRAM is write-protected from JLink | **Important** — must use ISP for all MRAM writes |
| `app-cpu-stubs.json` is the baseline sanity check | **Pattern** — always verify with known-good before debugging custom config |
| UART4 console needs J15 jumpers on AppKit | **Hardware** — no second serial port without them |
| DTB SRAM size must match actual hardware | **Critical** — mismatch causes double fault + brick |

## Remaining Work

1. **Get serial console working**: Install J15 jumpers on AppKit board, or add UART4 pinmux to app-device-config.json
2. **Fix DTB in Yocto source**: Patch the DTS file in the kernel recipe, not the binary
3. **Verify full boot**: Login prompt, networking, etc.
4. **ADB support**: Add to Yocto image, test USB OTG
5. **Automate the flash workflow**: Single script: gen-toc → maintenance mode → write-mram

## Patterns to Reuse

- **Baseline first**: When bringing up a new board, flash the vendor's factory test before your custom images
- **Compare known-good vs failing config**: Diff the working stubs JSON against the failing Linux JSON to find what's missing
- **JLink SWD as ground truth**: Core registers don't lie — PC, CPSR, and exception level tell you exactly where you are in the boot chain
- **Capture knowledge incrementally**: Don't wait until the end. Each session's learnings informed the next session's approach
- **Programmatic over manual**: Once you find the serial protocol, automate it. The ISP maintenance mode sequence saves significant time vs the interactive maintenance tool + physical button
