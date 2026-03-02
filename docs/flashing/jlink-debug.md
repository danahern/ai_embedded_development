# J-Link Debug Reference

## Device Names (SEGGER Database)

### E7 Family (AE722F80F55D5)

| Device Name | Core | Flash | RAM |
|-------------|------|-------|-----|
| `AE722F80F55D5_HE` | Cortex-M55 | 5.5 MB | 64 KB |
| `AE722F80F55D5_HP` | Cortex-M55 | 5.5 MB | 64 KB |
| `AE722F80F55D5_A32_0` | Cortex-A32 | — | 64 KB |
| `AE722F80F55D5_A32_1` | Cortex-A32 | — | 64 KB |
| `AE722F80F55D5_M55_HP` | Cortex-M55 | **Custom** (our Devices.xml) | 256 KB |

Our custom `_M55_HP` device adds OSPI FlashBank at 0xC0000000 and larger WorkRAM.

## Debug Access Points (AP)

| AP | Type | Target | Notes |
|----|------|--------|-------|
| AP[0] | AHB-AP | M55_HE | Not always accessible |
| AP[1] | APB-AP | Debug | CoreSight debug infrastructure |
| AP[2] | AXI-AP | System bus | Memory access, no CPU (cannot use with loadbin) |
| AP[3] | AHB-AP | M55_HP | **Used for MRAM/OSPI programming** |
| AP[4] | AHB-AP | (varies) | Additional core |

## Per-Core Setup

### Cortex-M55_HE (High Efficiency, 160 MHz)

| Setting | Value |
|---------|-------|
| Device | `AE722F80F55D5_HE` |
| Interface | JTAG (Ozone) or SWD |
| Speed | 4 MHz |
| FLASH | 0x80000000, 5.5 MB |
| RAM | 0x02000000, 64 KB (TCM) |
| Initial PC | **Read from Base Address Vector Table** (critical!) |
| Initial SP | Read from Base Address Vector Table |

**Prerequisite:** Debug stubs must be loaded first. Without stubs, J-Link cannot connect.

```bash
# Load debug stubs via SE-UART
app-gen-toc -f build/config/app-cpu-stubs.json
app-write-mram -r
```

**Ozone setup:**
1. New Project → AlifSemiconductor → `AE722F80F55D5_HE`
2. Register set: Cortex-M55 (with FPU) — auto-selected
3. Connection: JTAG, 4 MHz, USB
4. **Critical:** Initial PC → "Read from Base Address Vector Table" (not ELF Entry Point)

### Cortex-M55_HP (High Performance, 400 MHz)

| Setting | Value |
|---------|-------|
| Device (official) | `AE722F80F55D5_HP` |
| Device (custom) | `AE722F80F55D5_M55_HP` (includes OSPI FlashBank) |
| Interface | SWD |
| Speed | 4000 kHz (or auto) |
| AP | AP[3] |
| Debug base | 0xE00FF000 |
| WorkRAM | 0x00000000, 256 KB (ITCM) |

**Used for:** MRAM and OSPI programming via `loadbin`. The custom device definition includes the OSPI FlashBank.

**Custom Devices.xml:**
```xml
<ChipInfo Vendor="AlifSemi" Name="AE722F80F55D5_M55_HP"
          Core="JLINK_CORE_CORTEX_M55"
          WorkRAMAddr="0x00000000" WorkRAMSize="0x40000" />
<FlashBankInfo Name="OSPI1 Flash" BaseAddr="0xC0000000" AlwaysPresent="1">
  <LoaderInfo Name="Default" MaxSize="0x2000000"
              Loader="Ensemble_IS25WX256.FLM" LoaderType="FLASH_ALGO_TYPE_OPEN" />
</FlashBankInfo>
```

**Limitation:** M55_HP CPU cannot access OSPI controller at 0x83002000 — BusFault due to EXPMST bridge. Debug DAP can access (bypasses EXPMST), which is why the FLM works.

### Cortex-A32 (800 MHz, dual-core)

| Setting | Value |
|---------|-------|
| Device | `AE722F80F55D5_A32_0` or `AE722F80F55D5_A32_1` |
| Generic | `Cortex-A32` |
| Interface | JTAG |
| Speed | 4000 kHz |

**Read-only after SE boot.** MRAM becomes write-protected for A32 after boot. Use for register dumps and memory reads only, never for flash programming.

## SWD vs JTAG

| Context | Interface | Notes |
|---------|-----------|-------|
| M55 cores (our scripts) | SWD | `-if SWD -speed 4000` |
| M55 (Ozone example) | JTAG | Connection Settings dialog |
| A32 | JTAG | Standard for Cortex-A |
| Physical connector | 19-pin JTAG | SWD protocol works over JTAG connector |

## JLinkScript

Our custom script prevents J-Link from resetting during `loadbin`:

```c
int ResetTarget(void) {
  Report("Alif E7: Skipping reset (SE-managed boot)");
  return 0;
}
```

**Why:** Any SWD reset kills the SE boot sequence — AP[3] disappears, memory access fails. Only recovery is physical power cycle.

**Must be passed explicitly** (JLink V9.20 doesn't resolve paths from Devices.xml):
```bash
JLinkExe -device AE722F80F55D5_M55_HP -if SWD -speed 4000 -autoconnect 1 \
         -JLinkScriptFile /path/to/AlifE7.JLinkScript -NoGui 1
```

**Key flags:**
- `-NoGui 1` — prevents GUI probe selector popup on macOS
- `-autoconnect 1` — auto-connect to first probe

## Flash Programming via J-Link

### MRAM (direct loadbin, ~44 KB/s)

```
loadbin /path/to/bl32.bin 0x80002000
loadbin /path/to/appkit-e7.dtb 0x80010000
loadbin /path/to/xipImage 0x80020000
loadbin /path/to/cramfs-xip.img 0x80300000
verifybin /path/to/bl32.bin 0x80002000
```

Multiple writes per session — no power cycle needed between `loadbin` commands.

### OSPI (via FLM, ~7 KB/s)

Writes to addresses >= 0xC0000000 route through `Ensemble_IS25WX256.FLM`:
```
loadbin /path/to/cramfs.bin 0xC0000000
loadbin /path/to/kernel.bin 0xC0800000
```

Erase before write recommended (clears stale MTD data). Sector size: 64 KB.

## Known Gotchas

1. **Reset kills debug access** — always use JLinkScript with no-op ResetTarget
2. **A32 read-only** — write-protected after SE boot
3. **M55_HP fails when sleeping** — SWD access fails if firmware is sleeping/done
4. **File extension rejection** — `loadbin` rejects `.dtb`, `.img` — must rename to `.bin`
5. **"Failed to halt CPU"** — harmless, writes succeed
6. **Power cycle required** — before first connect and after flashing
7. **ATOC overwrites** — J-Link writes to ATOC-managed regions are overwritten on reboot
8. **connect-under-reset fails** — disrupts SE boot same as normal reset
9. **Ensemble.FLM fails** — `GetSectorInfo` error on JLink V8.70; not needed for MRAM (direct writes work)
10. **AXI-AP (AP[2])** — cannot use for `loadbin` (no CPU core associated)

## Device Definition Files

Installed to `~/Library/Application Support/SEGGER/JLinkDevices/AlifSemi/`:
- `Devices.xml` — custom `AE722F80F55D5_M55_HP` with OSPI FlashBank
- `AlifE7.JLinkScript` — no-op ResetTarget
- `Ensemble_IS25WX256.FLM` — OSPI flash algorithm (from CMSIS pack)

Setup: `alif-flash.jlink_setup(install=true)` or `claude-mcps/alif-flash/jlink/setup.sh`
