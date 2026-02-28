# Secure Enclave — AIPM Services, Power Gating, MHU Protocol

## Summary

The Alif Ensemble E7 Secure Enclave (SE) controls power domains and clock gating through the AIPM (Application Independent Power Management) subsystem. USB PHY power can be controlled either through SE services (Linux/Zephyr path via TF-A or driver) or through direct register writes (bare-metal path). The SE is accessed via MHU (Message Handling Unit) v2 mailbox protocol.

## Key Facts

- **SE Service IDs**: GET_RUN_CFG = 310, SET_RUN_CFG = 311 [S01, S07, S09]
- **USB in AIPM**: `phy_pwr_gating` bit 1 (USB_PHY), `ip_clock_gating` bit 6 (USB) [S07]
- **MHU v2**: Send 0x1B800000, Recv 0x1B810000, Shared payload at 0x02380000 [S01]
- **Power Domain**: USB in PD_SYST (PD6, value 0x40 in power_domains bitmask) [S07]
- **SE clock API**: `SERVICES_clocks_enable_clock(CLKEN_USB)` — dedicated enum for USB [S09]
- **Bare-metal bypass**: Direct register writes to VBAT/CLKCTL work without SE — TinyUSB does not use SE [S08]

## AIPM Run Profile

The `run_profile_t` structure controls system-wide power state. USB requires bits in three fields:

```c
typedef struct {
    uint32_t power_domains;       // Bitmask of PD0-PD9
    uint32_t dcdc_voltage;
    dcdc_mode_t dcdc_mode;
    lfclock_t aon_clk_src;
    hfclock_t run_clk_src;
    clock_frequency_t cpu_clk_freq;
    scaled_clk_freq_t scaled_clk_freq;
    uint32_t memory_blocks;
    uint32_t ip_clock_gating;     // Bitmask: bit 6 = USB
    uint32_t phy_pwr_gating;      // Bitmask: bit 1 = USB_PHY
    ioflex_mode_t vdd_ioflex_3V3;
} run_profile_t;
```

### USB-Required Bits

| Field | Bit | Mask | Purpose |
|---|---|---|---|
| `power_domains` | 6 | `0x40` | Enable PD_SYST power domain |
| `ip_clock_gating` | 6 | `0x40` | Enable USB IP clock |
| `phy_pwr_gating` | 1 | `0x02` | Enable USB PHY power |

### IP Clock Gating Enum

```c
typedef enum {
    NPU_HP=0, NPU_HE=1, ISIM=2, OSPI_1=3, CANFD=4,
    SDC=5, USB=6, ETH=7, GPU=8, CDC200=9,
    CAMERA=10, MIPI_DSI=11, MIPI_CSI=12, LP_PERIPH=13
} ip_clock_gating_t;
```

### PHY Power Gating Enum

```c
typedef enum {
    LDO_PHY=0, USB_PHY=1, MIPI_TX_DPHY=2,
    MIPI_RX_DPHY=3, MIPI_PLL_DPHY=4
} phy_gating_t;
```

## Service IDs

Full power service ID range: [S07]

| ID | Service | Purpose |
|---|---|---|
| 300 | STOP_MODE_REQ | Enter stop mode |
| 301 | EWIC_CONFIG | External wakeup interrupt controller |
| 302 | VBAT_WAKEUP_CONFIG | VBAT wakeup sources |
| 303 | MEM_RETENTION_CONFIG | Memory retention |
| 304 | M55_HE_VTOR_SAVE | M55-HE vector table save |
| 305 | M55_HP_VTOR_SAVE | M55-HP vector table save |
| 306 | GLOBAL_STANDBY | Corestone standby mode |
| 307 | MEMORY_POWER | SERAM/MRAM power control |
| 308 | DCDC_VOLTAGE | DCDC voltage control |
| 309 | LDO_VOLTAGE | LDO voltage control |
| **310** | **GET_RUN_CFG** | **Read current run profile (used for USB)** |
| **311** | **SET_RUN_CFG** | **Write run profile (used for USB)** |
| 312 | GET_OFF_CFG | Read off profile |
| 313 | SET_OFF_CFG | Write off profile |

Clock service: `SERVICES_clocks_enable_clock(CLKEN_USB)` provides a simpler alternative for clock-only control. [S09]

**WARNING — Service ID Off-By-One Bug**: Some local `services_lib_ids.h` copies start `STOP_MODE_REQ_ID` at 301 instead of 300, shifting all subsequent IDs by +1. If your local header says GET_RUN=311 and SET_RUN=312, those are WRONG. Correct values: **GET=310, SET=311**. Sending the wrong ID crashes the SE and hangs the A32 core. Always verify against the upstream Alif CMSIS DFP. [S13]

## MHU Protocol

### Message Format

```c
typedef struct {
    volatile uint16_t hdr_service_id;    // Service ID (e.g., 311)
    volatile uint16_t hdr_flags;
    volatile uint16_t hdr_error_code;    // 0 = success
    volatile uint16_t hdr_padding;
} service_header_t;

// For SET_RUN, the full message includes run_profile_t fields:
typedef struct {
    service_header_t header;
    volatile uint32_t send_power_domains;
    volatile uint32_t send_dcdc_voltage;
    // ... other fields ...
    volatile uint32_t send_ip_clock_gating;   // USB = bit 6
    volatile uint32_t send_phy_pwr_gating;    // USB_PHY = bit 1
    volatile uint32_t send_vdd_ioflex_3V3;
    volatile int      resp_error_code;
} aipm_set_run_profile_svc_t;
```

### MHU Addresses

| Channel | Address | Purpose |
|---|---|---|
| MHU Send | `0x1B800000` | APSS -> SE message send |
| MHU Recv | `0x1B810000` | SE -> APSS response receive |
| Shared Payload | `0x02380000` | Shared memory for message data |

### Send Sequence (from TF-A / Zephyr)

1. Write message to shared payload area
2. Cache flush the payload region
3. Send via IPM/MHU: `ipm_send(send_dev, wait, CH_ID, &global_address, size)`
4. Wait for response in recv channel
5. Read error code from response header

## TF-A USB PHY Enable Flow

TF-A's `service_enable_usb_phy()` performs a read-modify-write: [S01]

1. Call SE service 310 (GET_RUN_CFG) to read current `run_profile_t`
2. Set `phy_pwr_gating |= (1 << 1)` — enable USB PHY power
3. Call SE service 311 (SET_RUN_CFG) with modified profile
4. Direct register writes:
   - Clear `PWR_CTRL[16:17]` at `0x1A609008` — enable VBAT power + disable isolation
   - Clear `USB_CTRL2[8]` at `0x4903F0AC` — release PHY POR

**No runtime SMC/PSCI call exists for USB** — this is a one-shot init at boot. [S01]

## Zephyr Power Domain Control

Zephyr uses a proper power domain driver (`power_domain_alif.c`): [S07]

```c
// Read current config, modify domain bit, write back
ret = se_service_get_last_set_run_cfg(&runp);
runp.power_domains |= BIT(ALIF_PD_SYST);  // Enable PD6
ret = se_service_set_run_cfg(&runp);
```

## Power Domains

| PD | Name | Purpose |
|---|---|---|
| PD0 | VBAT_AON | Always-on domain |
| PD2 | SSE700_AON | SSE-700 always-on |
| PD3 | RTSS_HE | M55-HE subsystem |
| PD4 | SRAMS | Bulk SRAM |
| PD5 | SESS | Secure Enclave |
| **PD6** | **PD_SYST** | **System Top (USB, UART, SPI, I2C, ETH, SDHC)** |
| PD7 | RTSS_HP | M55-HP subsystem |
| PD9 | APPS | A32 application processor |

## SE Clock API

The SE also provides direct clock enable/disable: [S09]

```c
SERVICES_clocks_enable_clock(services_handle, CLKEN_USB, true, &error_code);
```

Clock enable enum values: CLKEN_SYSPLL, CLKEN_CPUPLL, CLKEN_ES0, CLKEN_ES1, CLKEN_HFXO_OUT, CLKEN_CLK_160M, CLKEN_CLK_100M, **CLKEN_USB**, CLKEN_HFOSC, CLKEN_SRAM0, CLKEN_SRAM1

## Open Questions

- Does `SERVICES_clocks_enable_clock(CLKEN_USB)` do the same thing as the two register writes (CGU_CLK_ENA[22] + PERIPH_CLK_ENA[20]), or is it a third path?
- What error codes does the SE return for USB-related failures?
- Is there a way to query USB PHY power state through SE services?

## Source References

[S01] TF-A, [S07] sdk-alif/hal_alif, [S08] TinyUSB, [S09] SE Host Services API — See [sources.md](sources.md)
