# Reset Mechanisms Reference

Complete reference for all reset paths on the Alif Ensemble E7/E8 SoC family.

**Sources:** Datasheet v2.12 (Section 3.8), HWRM v2.9, SWRM v1.8 (Sections 2.9, 3.2, 3.3, 4.8), SE Host Services API v1.109.0, AppKit schematic (220-00307-D1), DevKit schematic (220-00319-A1).

## Architecture Overview

The SE Cortex-M0+ is the ONLY core that executes after any system-level reset. All other cores (A32, M55-HP, M55-HE) are held in reset until the SE explicitly releases them.

**Key principle:** All reset paths that affect the SE result in a full boot sequence, including ATOC re-read from MRAM.

### Power Domains

| Domain | Contents | Survives NSRST? | Survives POR_N? |
|--------|----------|-----------------|-----------------|
| PD-0 (Always-On) | Debug logic, JTAG, AON peripherals | YES | NO |
| PD-1..PD-9 | CPU cores, memories, peripherals | NO | NO |

## Hardware Reset Sources

### POR_N Pin (Cold Reset)

- **Type:** Active-low input
- **Effect:** Full power-on cycle. **All** state lost including PD-0, debug, JTAG.
- **Boot path:** Cold boot — SEROM loads SERAM, validates, processes ATOC, boots all cores.
- **Board connection:** Physical reset button (SW1) on both AppKit and DevKit.

### NSRST Pin (Warm Reset)

- **Type:** Active-low input (datasheet: "JTAG reset / system reset")
- **Effect:** Resets all logic **except** PD-0 Always-On, debug logic, JTAG.
- **Boot path:** SE restarts from SEROM. Full ATOC re-read (SERAM not retained through NSRST).
- **Board connection:** J-Link sRST (pin 15 on JTAG connector) on both boards.

**From SWRM 4.8:** *"The hardware reset (through toggling the NSRST of the JTAG interface) is causing a **cold restart of the whole device**, not just the application being debugged."*

### BOR (Brown-Out Reset)

On E8 DevKit only: STM1061N17WX6F supervisor (U4) monitors VDD_MAIN, asserts POR_N if below ~1.7V. AppKit has no brownout supervisor.

## Physical Reset Button vs J-Link sRST

**They are on DIFFERENT nets but both trigger full SE re-boot.**

### Schematic Routing

| Signal | Net Name | SoC Pin | Driven By | Reset Type |
|--------|----------|---------|-----------|------------|
| Reset button (SW1) | **POR_N** | U18 (BGA194) | Button to GND + pull-up | Cold (POR) |
| J-Link sRST | **NSRST** | J10 (BGA194) | JLink-OB E1 + JTAG connector pin 10 | Warm (system) |

### AppKit-E7 (220-00307-D1)

```
SW1 ---+--- R39 (100K) --- V_1V8_R
       |
       +---> POR_N net ---> SoC pin POR_N

JLink-OB E1 (U21C) NSRST --+--> NSRST net ---> SoC pin NSRST
                             |
J17 external JTAG pin 10 ---+    R84 (100K) pull-up
```

### E8 DevKit (220-00319-A1)

```
SW1 ---+--- R31 (20K) --- VDDIO_1V8
       |
       +---> POR_N net ---> SoC pin POR_N
       |
       +---> U4 (STM1061N17) brownout supervisor on VDD_MAIN

JLink-OB E1 (U22C) NSRST --+--> NSRST net ---> SoC pin NSRST
                             |
J14 JTAG pin 10 ------------+    R108 (20K) pull-up
J15 compact JTAG pin 9 -----+
J19 "Plug of Nails" pin 4 --+
```

No RC filters on any reset line. No cross-connection between POR_N and NSRST.

### Functional Comparison

| Property | Reset Button (POR_N) | J-Link sRST (NSRST) |
|----------|---------------------|---------------------|
| PD-0 AON domain | Reset | Preserved |
| Debug/JTAG logic | Reset | Preserved |
| SE boot sequence | Cold boot | Cold boot |
| ATOC re-read | YES | YES |
| Debugger connection | Lost | Lost (per SWRM 4.8) |

**Practical difference is minimal:** both cause full SE cold boot with ATOC re-read. POR_N additionally resets AON and debug domains.

## Software Reset Sources

| Source | Scope | SE Restarts? | ATOC Re-read? |
|--------|-------|-------------|--------------|
| SE Reset (internal) | All except PD-0 | Yes | Yes |
| SW_HOST_RST | All except PD-0, SE, debug | No (SE stays) | SE can re-process |
| SW_HP_RST | RTSS-HP only (M55-HP + NPU) | No | No |
| SW_HE_RST | RTSS-HE only (M55-HE + NPU) | No | No |
| SERVICES_boot_reset_soc | Entire SoC | Yes | Yes |
| SERVICES_boot_reset_cpu | Single core | No | No |

## J-Link Reset Commands

### Direct Pin Control (Bypass JLinkScript)

These directly drive pin 15 and are **NOT** intercepted by `ResetTarget()`:

| Command | Alias | Action |
|---------|-------|--------|
| `ClrRESET` | `R0` | Assert nRST (pull LOW — hold target in reset) |
| `SetRESET` | `R1` | Release nRST (pull HIGH — target exits reset) |

### Reset Strategies (via `RSetType`)

| Type | Name | Mechanism |
|------|------|-----------|
| 0 | Normal (default) | Auto-selects; calls `ResetTarget()` from JLinkScript if present |
| 1 | Core + Peripherals | SYSRESETREQ via AIRCR register |
| 2 | Core Only | VECTRESET via AIRCR register |
| 3 | Reset Pin | Toggles nRST pin with ~20ms pulse |

### Our JLinkScript (No-Op Reset)

File: `claude-mcps/alif-flash/jlink/AlifE7.JLinkScript`

```c
int ResetTarget(void) {
  Report("Alif E7: Skipping reset (SE-managed boot)");
  return 0;
}
```

**Why:** During `loadbin`, J-Link's default behavior would reset the target. On Alif, resetting via SWD kills AP[3] (M55_HP debug access) because the SE hasn't re-enabled it yet. Only recovery is a physical power cycle. The no-op prevents this.

**When it applies:** Only when using `-Device AE722F80F55D5_M55_HP` (our custom device). Does NOT apply when using `-Device Cortex-A32` (generic device, no JLinkScript loaded).

### Existing `reset_via_jlink()` Function

File: `claude-mcps/alif-flash/src/alif_flash/isp.py` (line 145)

Uses `-Device Cortex-A32` deliberately — bypasses our JLinkScript no-op. Sends `r` (reset) command, which uses the default hardware reset strategy for A32 targets (toggles nRST pin). This triggers a full SE re-boot.

Used in the `enter_maintenance` flow to get the SE back into ISP-responsive state.

### How to Reset via J-Link Command Line

```bash
# Option 1: Direct pin toggle (explicit)
echo -e "ClrRESET\nSleep 100\nSetRESET\nSleep 2000\nexit" > /tmp/reset.jlink
JLinkExe -Device Cortex-A32 -If SWD -Speed 4000 -AutoConnect 1 \
         -NoGui 1 -CommandFile /tmp/reset.jlink

# Option 2: Default reset strategy for Cortex-A32 (simpler)
echo -e "r\nSleep 2000\nexit" > /tmp/reset.jlink
JLinkExe -Device Cortex-A32 -If SWD -Speed 4000 -AutoConnect 1 \
         -NoGui 1 -CommandFile /tmp/reset.jlink
```

**After reset:** Debug access is lost for ~2-3 seconds while the SE completes its boot sequence. You must reconnect after the SE enables cores per ATOC.

## Debug Reset Recommendations (from SWRM 4.8)

| Method | Use When |
|--------|----------|
| **SYSRESETREQ** | Iterative M55 debugging — resets core + peripherals, may skip SE boot |
| **VECTRESET** | Fastest — resets core only, peripherals keep state |
| **HW RESET (NSRST)** | After flashing new ATOC/firmware — need full SE re-boot |

**Never use HW RESET for iterative debugging** — it restarts the entire boot chain and loses the debugger connection.

## probe-rs Reset Capabilities

Our `embedded-probe` MCP's `reset` tool calls `core.reset()` (SYSRESETREQ). The `reset_type` parameter ("hardware"/"software") is currently cosmetic — both paths call the same function. To use hardware nRST, probe-rs would need `Probe::target_reset_assert()`/`target_reset_deassert()`, which are not exposed in the MCP.

## SE Host Services Boot APIs

| API | Description |
|-----|-------------|
| `SERVICES_boot_reset_soc` | Full SoC reset (does not return) |
| `SERVICES_boot_reset_cpu(cpu_id)` | Reset single core (stops it) |
| `SERVICES_boot_release_cpu(cpu_id)` | Release core from reset |
| `SERVICES_boot_process_toc_entry(image_id)` | Process deferred ATOC entry at runtime |
| `SERVICES_boot_cpu(cpu_id, address)` | Start core at address (no ATOC) |

**M55 restart sequence:** `set_vtor` → `reset_cpu` → reload image → `release_cpu`

## Linux Reboot

**Not currently supported.** TF-A `e7_pm.c` implements `.system_off` (WFI halt) but NOT `.system_reset`. To enable `reboot`:
- Add `.system_reset` handler to `plat_arm_psci_pm_ops`
- Call `SERVICES_boot_reset_soc` via MHU

## Complete Reset Path Summary

| Reset Source | Type | SE Restarts? | ATOC Re-read? | Debug Preserved? |
|-------------|------|-------------|--------------|-----------------|
| POR_N (reset button) | HW Cold | Yes | Yes | No |
| NSRST (J-Link sRST) | HW Warm | Yes | Yes | Yes (but connection lost) |
| VBAT_POR | HW Cold | Yes | Yes | No |
| BOR (brown-out) | HW Cold | Yes | Yes | No |
| SE Reset (SW) | SW Warm | Yes | Yes | Yes |
| SW_HOST_RST | SW Warm | No (SE stays) | SE re-processes | Yes |
| SW_HP_RST | SW Partial | No | No | Yes |
| SW_HE_RST | SW Partial | No | No | Yes |
| SERVICES_boot_reset_soc | API | Yes | Yes | TBD |
| SERVICES_boot_reset_cpu | API | No | No | Yes |
| SYSRESETREQ (debug) | SW Register | Depends | Depends | Yes |
| VECTRESET (debug) | SW Register | No | No | Yes |
| PSCI SYSTEM_RESET | SMC | Not implemented | N/A | N/A |
