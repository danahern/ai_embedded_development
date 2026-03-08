# Plan: UART Console Bringup on Alif E7 Linux OSPI Boot

**Status:** Complete

## Problem Statement

Linux kernel boots on Alif E7 (OSPI XIP) but has no UART console output. The 8250_dw driver doesn't probe. Multiple pipeline issues have been discovered:

1. DTS fixes not propagating from git source to Yocto work-shared
2. Built DTB not collected to setools flash staging area
3. MRAM not reflashed after DTB changes → kernel can't find DTB → "no ATAGS support: can't continue"

## Architecture

```
Git source (linux_alif/)
  → Yocto work-shared (container)
    → Yocto build output (deploy/)
      → setools/build/images/ (host)
        → MRAM 0x80200000 (SE-UART flash)
          → RAM 0x02390000 (TF-A copies)
            → Kernel parses DTB
```

## Current Approach: DTB Patching via dtc

Instead of rebuilding via Yocto (which has propagation issues), we decompile the known-working `devkit-e7-ospi.dtb`, patch it with dtc, and recompile. This ensures the correct memory layout is preserved.

## Root Causes Discovered

### 1. Kernel Abort with Yocto-built DTB (SOLVED)
**The devkit-e8.dts declares 64MB HyperRAM, but the AppKit-E7 only has 32MB.**
Using the previously-working `devkit-e7-ospi.dtb` (32MB HyperRAM, 3 memory regions) fixes the abort.

### 2. earlycon Baud Rate Bug (SOLVED)
**`earlycon=uart8250,mmio32,0x4901a000,115200` overwrites TF-A's correct baud rate divisor.**

- TF-A configures UART2 with divisor=54 (DLL=0x36) for 115200 baud with 100 MHz UART clock
- earlycon assumes default `uartclk=1843200` Hz, calculates divisor = 1843200/(16*115200) = **1**
- With actual 100 MHz clock, divisor=1 gives baud rate = 100MHz/16 = 6.25 Mbaud (way too fast)
- **Fix:** Remove baud rate from earlycon: `earlycon=uart8250,mmio32,0x4901a000` (no `,115200`)
- This makes earlycon read TF-A's divisor and preserve it

### 3. ttyS0 Not Registering — Deferred Probe Chain (IN PROGRESS)
**8250_dw driver can't probe because of cascading dependency failures:**

```
MHU driver → "Invalid compatible property" (error -22)
  → SE host services can't communicate with SE
    → psclks clock provider never registers
      → 8250_dw can't get "baudclk" clock → -EPROBE_DEFER
        → Also: pinctrl provider can't register (needs clocks too)
          → pinctrl_bind_pins() returns -EPROBE_DEFER
            → 8250_dw probe blocked BEFORE driver code even runs
```

**MHU root cause:** DTB has `compatible = "arm,mhuv2", "arm,primecell"` but upstream kernel 6.12 arm-mhuv2 driver requires `"arm,mhuv2-tx"` or `"arm,mhuv2-rx"`. The DTB was built for Alif's kernel fork which has a custom MHU driver.

**Workaround (current attempt):** Remove `clocks`, `clock-names`, `pinctrl-0`, `pinctrl-names` from UART2 node, add `clock-frequency = <100000000>`. TF-A already configured the UART2 pins and clock, so the driver should work without these dependencies.

### 4. UART clock = 100 MHz (CONFIRMED)
- Verified via JLink reading DLL=0x36 (divisor 54) after TF-A boot
- uartclk = 16 * 54 * 115200 = 99,532,800 ≈ 100 MHz
- Matches arch_timer: "running at 100.00MHz"

## Step-by-Step Progress

### Phase 1-2: DTB Pipeline + Kernel Config (COMPLETE)
- [x] Steps 1-7: All completed in previous session
- [x] DTB built from Yocto with UART2 + earlycon + HyperRAM fixes
- [x] Kernel config has DEVTMPFS_MOUNT=y and LOG_BUF_SHIFT=16

### Phase 3: Flash and Verify (COMPLETE)
- [x] **Step 8-11**: Flash + verify FDT in MRAM + RAM ✓
- [x] **Step 12-13**: Kernel aborts — 64MB HyperRAM in Yocto DTB

### Phase 4: Fix Memory Layout (COMPLETE)
- [x] **Step 14**: Switched to working `devkit-e7-ospi.dtb` (32MB HyperRAM)
  - Kernel boots to /sbin/init ✓
  - But no UART output, no ttyS0

### Phase 5: earlycon Fix (COMPLETE)
- [x] **Step 15**: Decompile working DTB, add `aliases { serial0 }` and earlycon
  - First attempt: `earlycon=...,115200` → no output (divisor=1 bug)
  - Fixed: `earlycon=...,0x4901a000` (no baud) → TF-A + kernel boot output on UART2 ✓
- [x] **Step 16**: Full kernel boot log visible on UART2 at 115200 baud ✓
  - TF-A: OSPI configured, HyperRAM configured, USB clocks enabled
  - Kernel: boots fully, 2 CPUs, 37MB RAM, cramfs root mounted
  - Error: "Warning: unable to open an initial console" (no ttyS0)

### Phase 6: Fix ttyS0 Registration (IN PROGRESS)
- [x] **Step 17a**: Identified root cause — MHU → clock → pinctrl → 8250_dw defer chain
- [x] **Step 17b**: Added `clock-frequency = <100000000>` to UART2 node, removed clocks
  - Result: still no ttyS0 (pinctrl deferred probe was the actual blocker)
- [x] **Step 17c**: Removed `pinctrl-0` and `pinctrl-names` from UART2 node
  - **ttyS0 REGISTERED!** `4901a000.uart2: ttyS0 at MMIO 0x4901a000 (irq=78, base_baud=6250000) is a 16550A`
  - earlycon→ttyS0 handoff: `printk: legacy console [ttyS0] enabled` / `bootconsole [uart8250] disabled`
  - Full boot to interactive shell prompt: "Press Enter to activate this console"
  - Root cause confirmed: pinctrl deferred probe was the blocker (not clocks)
- [x] **Step 17d**: ttyS0 registered and console works ✓
- [x] **Step 18**: Interactive shell available on UART2 ✓
  - Init scripts run: overlayfs, helloworld app, USB gadget (no UDC)
  - Login prompt: "Please press Enter to activate this console"

## DTB Patch Summary (current patched DTB)

Starting from known-working `devkit-e7-ospi.dtb` (model "devkit-e7", 32MB HyperRAM):

1. Added `aliases { serial0 = "/apb@49010000/uart2@4901A000"; }`
2. Changed bootargs: `earlycon=uart8250,mmio32,0x4901a000` (NO baud rate)
3. UART2 node: removed `clocks`, `clock-names`, `pinctrl-0`, `pinctrl-names`
4. UART2 node: added `clock-frequency = <100000000>`
5. Memory layout unchanged: `reg = <0x2000000 0x400000 0x8010000 0x26f000 0xa0000000 0x2000000>`

## Boot Log Analysis (with earlycon working)

Key messages from successful earlycon boot:
```
Serial: 8250/16550 driver, 8 ports, IRQ sharing disabled    ← base driver loaded
                                                              ← NO ttyS0 registration
arm-mhuv2 1b000000.mhu: Invalid compatible property          ← MHU fails (x6)
arm-mhuv2 1b000000.mhu: probe with driver arm-mhuv2 failed with error -22
clk: Disabling unused clocks                                 ← clock framework cleanup
Warning: unable to open an initial console.                   ← no /dev/console
cramfs: linear cramfs image on mtd:physmap-flash.0 appears to be 4924 KB
VFS: Mounted root (cramfs filesystem) readonly on device 31:0.
devtmpfs: mounted
Run /sbin/init as init process
overlayfs: failed to set up upper                             ← overlayfs needs writable layer
```

## TODOs (after console works)

- [ ] Fix MHU compatible strings in DTS for upstream kernel (proper long-term fix)
- [ ] Clean up ~40 test configs in `tools/setools/build/config/`
- [ ] Consolidate setools directories (eliminate `firmware/linux/alif-e7/setools/` confusion)
- [ ] Create proper AppKit-E7 Yocto machine config (currently uses devkit-e8)
- [ ] Document correct DTS/DTB for each board variant
- [ ] Fix overlayfs (needs writable upper layer — probably needs tmpfs or writable partition)
- [ ] Investigate CPU1 "failed to come online" (intermittent — worked in some boots)

## Key Addresses

| What | Physical | Virtual | Notes |
|------|----------|---------|-------|
| SRAM start | 0x02000000 | 0xC0000000 | PAGE_OFFSET=0xC0000000, PHYS_OFFSET=0x02000000 |
| OSPI kernel | 0xC0800000 | 0xBF800000 | XIP text |
| DTB in MRAM | 0x80200000 | — | SE writes here from ATOC |
| DTB in RAM | 0x02390000 | 0xC0390000 | TF-A copies here |
| TFA in MRAM | 0x80002000 | — | bl32-ospi.bin |
| __log_buf | 0x0206A020 | 0xC006A020 | Current kernel (may change if rebuilt) |
| UART2 base | 0x4901A000 | — | 8250 MMIO, clock=100MHz, divisor=54 |

## Serial Ports

- SE-UART: `/dev/cu.usbserial-A10LOVM2` — 57600 baud
- UART2/A32 console: `/dev/cu.usbserial-BG03TY04` — 115200 baud

## Config Files

- ATOC config: `tools/setools/build/config/linux-boot-e7-ospi.json`
- Kernel OSPI config: `tools/setools/build/config/kernel-ospi-only.json`
- Kernel cfg fragment: `meta-eai/recipes-kernel/linux/files/console-debug.cfg`
- Patched DTS source: `/tmp/devkit-e7-ospi.dts`

## JLink Access (for debugging)

- **Use M55_HP** (`AE722F80F55D5_HP`) with JLinkScript — NOT M55_HE or A32_0
- JLink V9.20 can't connect to A32_0 (debug registers not found)
- M55_HP can read all physical memory including SRAM (kernel log buffer)
- Must use JLinkScript to prevent reset: `-JLinkScriptFile "$HOME/Library/Application Support/SEGGER/JLinkDevices/AlifSemi/AlifE7.JLinkScript"`
