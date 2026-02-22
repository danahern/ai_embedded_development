# OpenClaw Dev Kit — Board Family Plan

Status: In-Progress
Created: 2026-02-21

## Context

[OpenClaw](https://openclaw.ai/) is an open-source AI assistant (Node.js gateway, WS port 18789, SOUL.md personality system). [PicoClaw](https://github.com/sipeed/picoclaw) is a Go rewrite (<10MB RAM). The [ClawBox](https://openclaw-hardware.com/) (€399, Jetson Orin Nano) is the only dedicated hardware, and it's a sealed consumer box.

**Goal:** Design a **family of boards** at different price/capability tiers for self-hosting OpenClaw, leveraging hardware we already have infrastructure for (STM32MP1, Alif E7, nRF7002/nRF5340, ESP32, RPi). Each board stores personality/memory on-device, connects to the internet, and hosts the gateway directly — no pass-through.

## Software Requirements by Tier

| Requirement | PicoClaw (Go) | Full OpenClaw (Node.js) |
|-------------|---------------|------------------------|
| OS | Linux (any) | Linux (any) |
| RAM minimum | ~64MB (10MB binary + OS) | ~512MB (Node.js + gateway) |
| Storage | 128MB+ | 2GB+ |
| Runtime | Single Go binary | Node.js >= 22 |
| Personality | SOUL.md, IDENTITY.md, memory/ | Same |
| Gateway | Built-in multi-channel bot | WS server on port 18789 |
| Local inference | Not built-in (cloud only) | Local model support via config |

## Board Family

### Tier 1: "Pico" — ESP32-S3 Voice Frontend (~$10-15 BOM)

**NOT self-hosted.** Thin client that connects to an OpenClaw gateway on the LAN or cloud.

| | Spec |
|-|------|
| SoC | ESP32-S3 (Xtensa LX7, 512KB SRAM, PSRAM) |
| Connectivity | WiFi + BLE built-in |
| Audio | PDM mic + I2S speaker |
| Role | Wake word detection → stream audio to gateway, play TTS response |
| Software | ESP-IDF or Zephyr, custom firmware |
| Uses existing | ESP-IDF infra, `esp-idf-build` MCP, `eai_audio` HAL |

**Why include:** Cheapest entry point. Pairs with any Tier 3-5 board as a remote mic/speaker. Reuses existing ESP32 firmware infrastructure. Not a standalone OpenClaw host — requires a gateway somewhere on the network.

---

### Tier 2: "Nano" — nRF5340 + nRF7002 Companion (~$18-25 BOM)

**NOT self-hosted.** Zephyr-based thin client with BLE + WiFi.

| | Spec |
|-|------|
| SoC | nRF5340 (Cortex-M33, 512KB SRAM + 64KB net core) |
| WiFi | nRF7002 (WiFi 6 companion IC via QSPI) |
| BLE | nRF5340 net core (BLE 5.3) |
| Audio | PDM mic + I2S codec |
| Role | BLE provisioning, WiFi uplink to gateway, voice frontend |
| Software | Zephyr |
| Uses existing | `zephyr-build` MCP, `wifi_prov` lib, `eai_ble` HAL, nRF7002-DK infra |

**Why include:** We already have the nRF7002-DK and full Zephyr infrastructure. Same wifi_prov BLE protocol. Ultra-low power (~10mW sleep). Battery-powered satellite mic that talks to any Tier 3-5 gateway. Uses existing `wifi_provision` app as starting point.

---

### Tier 3: "Edge" — Alif E7 + nRF5340/nRF7002 (~$30-40 BOM)

**Self-hosted PicoClaw. Battery-powered. On-chip NPU.**

| | Spec |
|-|------|
| SoC | Alif Ensemble E7 (2x Cortex-A32 + 2x Cortex-M55 + Ethos-U55 NPU) |
| RAM | 4MB SRAM + **64MB OSPI PSRAM (APS51216O)** + 5.7MB MRAM |
| Storage | MRAM (XIP kernel + cramfs rootfs) + external SPI flash for personality |
| WiFi | nRF7002 (WiFi 6) via nRF5340 host |
| BLE | nRF5340 (BLE 5.3) |
| Audio | M55 core running `eai_audio` with PDM mic + I2S codec |
| Gateway | **PicoClaw** (Go binary, <10MB in 64MB PSRAM) |
| Local inference | Ethos-U55 NPU on M55 — wake word, keyword, small classifiers |
| Power | Ultra-low power A32 cores. Battery viable (LiPo). MRAM = instant-on. |
| Software | Yocto (existing `meta-alif`), Zephyr on M55 cores |

**Why include:** Unique in the lineup — the only tier with an on-chip NPU AND battery operation. The 64MB OSPI PSRAM (APS51216O) gives PicoClaw plenty of room (needs ~10MB, OS + userspace in remaining ~50MB). Kernel runs XIP from MRAM — zero boot-time RAM cost for code. The M55+Ethos-U55 handles wake word and audio preprocessing without waking A32 cores, extending battery life.

**Architecture:**
```
[A32: Linux + PicoClaw] <--MHU/eai_ipc--> [M55: Zephyr + eai_audio + Ethos-U55]
         |                                           |
    [nRF5340 via SPI/UART]                     PDM mic + I2S speaker
         |                                     Wake word (always-on)
    [nRF7002 via QSPI]                        Keyword/intent inference
         |
    WiFi → internet → cloud LLM
```

**Unique advantages:**
- Lowest power self-hosted option in the family
- NPU does useful work without cloud (wake word, intent classification)
- M55 cores stay awake for audio while A32 sleeps → sip-level standby
- MRAM is non-volatile — instant resume, no boot delay
- Reuses ALL existing Alif E7 infra (Yocto, SETOOLS, eai_ipc, board profile)

**Constraints:**
- 64MB PSRAM is slower than DDR — fine for PicoClaw, not for Node.js
- Full OpenClaw (Node.js) won't fit — PicoClaw only
- External SPI flash needed for personality/memory storage (MRAM space is for kernel)
- Cloud-only LLM for text generation (Ethos-U55 handles only small inference tasks)

---

### Tier 4: "Mini" — STM32MP1 + nRF7002 shield (~$30-45 BOM)

**Self-hosted PicoClaw.** First tier that runs the gateway on-device.

| | Spec |
|-|------|
| SoC | STM32MP157 (Cortex-A7 @ 650MHz + Cortex-M4) |
| RAM | 512MB DDR3L |
| Storage | SD card (rootfs + personality) |
| WiFi | nRF7002 shield via SPI, or USB WiFi dongle |
| BLE | nRF5340 on shield, or USB BT dongle |
| Audio | USB mic/speaker, or M4 running I2S audio via eai_audio |
| Gateway | **PicoClaw** (Go binary, <10MB RAM) |
| Local inference | None (cloud LLM only — A7 too weak) |
| Software | Yocto (existing `meta-eai` layer, `linux-build` MCP) |
| M4 core | Zephyr — real-time audio processing, sensor fusion via `eai_ipc` |

**Why include:** We have mature STM32MP1 infrastructure: Yocto builds, Docker cross-compilation, linux-build MCP (17 tools), ADB gadget, eai_ipc for A7↔M4 messaging. 512MB DDR3L is comfortable for PicoClaw + Linux. The M4 core running Zephyr gives real-time audio/sensor capability that pure-Linux boards lack.

**Architecture:**
```
[A7: Linux + PicoClaw] <--eai_ipc--> [M4: Zephyr + eai_audio + sensors]
         |
    [nRF7002 shield or USB WiFi] → internet → cloud LLM
```

**Connectivity options:**
1. nRF7002 shield (SPI) — reuses existing driver work, adds BLE via nRF5340
2. USB WiFi dongle (RTL8188EU etc.) — simplest, Linux driver, no custom HW
3. Ethernet (built-in on STM32MP1-DK) — wired, most reliable for stationary use

---

### Tier 5: "Dev" — Raspberry Pi 4/5 (~$50-80 BOM)

**Self-hosted full OpenClaw.** The easy on-ramp.

| | Spec |
|-|------|
| SoC | BCM2711 (Pi 4) or BCM2712 (Pi 5) |
| RAM | 4GB or 8GB |
| Storage | SD card or USB SSD |
| Connectivity | WiFi 5/6 + BT 5.0 built-in, GbE |
| Audio | USB mic/speaker, or I2S HAT |
| Gateway | **Full OpenClaw** (Node.js) or PicoClaw |
| Local inference | CPU-only (slow), or USB AI accelerator (Coral/Hailo) |
| Software | Raspberry Pi OS or Armbian |

**Why include:** Lowest barrier to entry. Everyone has one. No custom hardware needed — just flash an SD card. Full OpenClaw with Node.js 22. 4-8GB RAM handles gateway + local small model. The official OpenClaw docs already cover RPi setup. Our value-add: pre-built image with personality templates, audio config, OLED status display.

**Optional add-ons:**
- Google Coral USB (4 TOPS) or Hailo-8L M.2 HAT (13 TOPS) for local inference
- nRF5340+nRF7002 USB dongle for BLE provisioning
- ReSpeaker 2-Mic Pi HAT for voice

---

### Tier 6: "Pro" — RK3576 Custom Carrier (~$99-129 BOM)

**Self-hosted full OpenClaw + on-chip NPU.** The reference design.

| | Spec |
|-|------|
| SoC | RK3576 (4x A72 + 4x A53, 6 TOPS NPU) |
| RAM | 4GB LPDDR5 (default), 8GB option |
| Storage | 32GB eMMC + microSD + M.2 NVMe |
| Connectivity | WiFi 6 + BT 5.2 (on SoM), GbE |
| Audio | 2x MEMS mic (I2S) + MAX98357A amp + speaker + 3.5mm |
| Gateway | **Full OpenClaw** (Node.js) + PicoClaw option |
| Local inference | RKNN-LLM: TinyLlama 1.1B @ 10-15 tok/s on NPU |
| M.2 upgrade | RK1820 (20 TOPS, $30-40) → Qwen 3B @ 20+ tok/s |
| Software | Yocto with `meta-openclaw` layer |

**Why include:** Purpose-built for OpenClaw. Best price/performance for self-hosted AI. A72 cores handle Node.js well. 6 TOPS NPU enables useful local inference. M.2 slot scales to serious on-device LLM via RK1820/RK1828. Open-source carrier board (KiCad). Custom audio subsystem for voice interaction.

**Carrier board adds (over bare SoM):**
- Audio: 2x MEMS mics, I2S amp, speaker, 3.5mm jack
- M.2 Key M (NVMe or AI accelerator)
- M.2 Key B footprint (cellular, not populated)
- 40-pin GPIO (RPi-compatible where possible)
- MIPI CSI camera, Qwiic I2C
- UART debug header, USB-C PD
- 1.3" OLED status display
- ~100mm x 80mm, 4-layer PCB

---

### Tier 6+: "Ultra" — RK3588S SoM swap (~$179-249)

Same carrier board as Tier 6, with upgraded SoM:

| | RK3576 (Tier 6) | RK3588S (Tier 6+) |
|-|------------------|-------------------|
| CPU | 4x A72 + 4x A53 | 4x A76 + 4x A55 |
| NPU | 6 TOPS | 6 TOPS |
| RAM | 4-8GB | 8-16GB |
| eMMC | 32GB | 64GB |
| Local LLM | 1.1B | 3-7B (with RK1828) |

## Comparison to ClawBox

| | ClawBox | T3 Edge (E7) | T4 Mini (MP1) | T5 Dev (RPi) | T6 Pro (RK3576) |
|-|---------|--------------|---------------|---------------|-----------------|
| Price | €399 | ~$35 | ~$40 | ~$60-80 | ~$99-129 |
| Gateway | Full OpenClaw | PicoClaw | PicoClaw | Full OpenClaw | Full OpenClaw |
| RAM | 8GB | 68MB | 512MB | 4-8GB | 4-8GB |
| Local LLM | 7B CUDA | Ethos-U55 (small) | Cloud only | CPU (slow) | 1.1B on NPU |
| Battery | No | Yes (ultra-low power) | No | No | Optional |
| Audio | Built-in | M55 PDM+I2S | USB or M4 I2S | HAT or USB | Custom onboard |
| Hardware | Sealed box | Custom PCB | DK1 + shield | Pi + HAT | Custom open HW |
| Design files | Proprietary | Open KiCad | N/A (existing) | N/A (existing) | Open KiCad |

## Implementation Phases

### Phase 0: Software validation on existing hardware (no new purchases) ← CURRENT

Use what we already have:

1. **STM32MP1-DK1** — Install PicoClaw Go binary on existing Yocto image
   - Cross-compile PicoClaw for ARM (A7, `arm-linux-gnueabihf`)
   - Add PicoClaw recipe to `meta-eai`
   - Connect via Ethernet (built-in) or USB WiFi dongle
   - Validate: gateway starts, connects to Telegram, chat works with cloud Claude
   - Validate: SOUL.md personality loads, memory persists across reboot

2. **Alif E7 DevKit** — PicoClaw on E7 Linux with 64MB PSRAM
   - Modify Yocto image to enable 64MB OSPI PSRAM (APS51216O) in DTB
   - Cross-compile PicoClaw for ARM (A32, `arm-linux-gnueabihf -mcpu=cortex-a32`)
   - Validate PicoClaw fits in available RAM (kernel XIP + PicoClaw in PSRAM)
   - Connect via USB WiFi dongle initially (nRF7002 integration in Phase 2)

3. **Raspberry Pi** (if available) — Install full OpenClaw via npm
   - Standard Node.js 22 install
   - Validate full gateway with all features

### Phase 1: Audio + voice pipeline
- USB mic + speaker on STM32MP1 or RPi
- M55 core on Alif E7 running `eai_audio` with PDM mic + I2S codec
- whisper.cpp STT → PicoClaw/OpenClaw → Piper TTS
- Validate end-to-end voice interaction

### Phase 2: Wireless integration
- nRF5340+nRF7002 module as WiFi/BLE frontend for Alif E7 (SPI/UART bridge)
- ESP32-S3 voice thin client firmware (ESP-IDF, reuse `eai_audio`)
- nRF5340+nRF7002 thin client firmware (Zephyr, reuse `wifi_prov` + `eai_audio`)
- Protocol: WebSocket or TCP stream to gateway on LAN

### Phase 3: Alif E7 "Edge" board (Tier 3)
- KiCad: Alif E7 + 64MB PSRAM + nRF5340/nRF7002 + audio + battery
- Small form factor (~50x50mm or smaller)
- LiPo charge controller + power management
- Prototype fabrication (JLCPCB)

### Phase 4: RK3576 "Pro" board (Tier 6)
- Buy Radxa ROCK 4D (~$40-58) for software validation
- Add `meta-rockchip` to Yocto Docker build, port `meta-openclaw` recipes
- Validate RKNN-LLM local inference
- KiCad: Custom carrier with audio, M.2, OLED, GPIO
- Prototype fabrication

## Existing Infrastructure to Reuse

| Asset | Path | Used by |
|-------|------|---------|
| Yocto layer pattern | `firmware/linux/yocto/meta-eai/` | Tier 3, 4, 6 |
| Alif E7 Yocto config | `yocto-build/build-alif-e7/conf/` | Tier 3 |
| Alif E7 board profile | `knowledge/boards/alif_e7_devkit.yml` | Tier 3 |
| STM32MP1 board profile | `knowledge/boards/stm32mp157d_dk1.yml` | Tier 4 |
| Linux build MCP (17 tools) | `claude-mcps/linux-build/` | Tier 3, 4, 5, 6 |
| Docker cross-compilation | `firmware/linux/docker/Dockerfile.alif-e7` | Tier 3, 6 |
| eai_audio HAL | `firmware/lib/eai_audio/` | Tier 1, 2, 3, 4 |
| eai_ipc (A32↔M55, A7↔M4) | `firmware/lib/eai_ipc/` | Tier 3, 4 |
| wifi_prov (BLE provisioning) | `firmware/lib/wifi_prov/` | Tier 1, 2, 3 |
| eai_ble HAL | `firmware/lib/eai_ble/` | Tier 1, 2, 3 |
| ESP-IDF build MCP | `claude-mcps/esp-idf-build/` | Tier 1 |
| Zephyr build MCP | `claude-mcps/zephyr-build/` | Tier 2, 3, 4 |
| Alif E7 Linux plan | `plans/alif-e7-linux.md` | Tier 3 |
| Multi-board scaling pattern | `plans/linux-platform-scaling.md` | Tier 4, 6 |
| SETOOLS flash | `claude-mcps/alif-flash/` | Tier 3 |

## Verification

### Phase 0 (Software on existing HW)
- [x] PicoClaw cross-compiles for armhf (A7 + A32) — 15MB armv7, 16MB arm64
- [x] Yocto recipe (picoclaw-bin_1.0.bb) created in meta-eai
- [x] STM32MP1 local.conf updated with picoclaw-bin in IMAGE_INSTALL
- [x] Build script + Docker target for reproducible cross-compilation
- [x] Alif E7 constraints documented (15MB binary > 5.7MB MRAM, needs runtime loading)
- [ ] PicoClaw binary runs on STM32MP1 Yocto image (512MB DDR3L)
- [ ] PicoClaw binary runs on Alif E7 Linux (64MB PSRAM)
- [ ] Gateway connects to Telegram/Discord
- [ ] Chat works with cloud Claude API
- [ ] SOUL.md personality loads and is reflected in responses
- [ ] Memory persists across reboot

### Phase 1 (Voice)
- [ ] USB mic → whisper.cpp → text on STM32MP1 or RPi
- [ ] M55 PDM mic → eai_ipc → A32 PicoClaw on Alif E7
- [ ] Text → Piper TTS → speaker output

### Phase 2 (Wireless)
- [ ] nRF5340+nRF7002 provides WiFi to Alif E7 via SPI/UART
- [ ] ESP32-S3 thin client streams audio to gateway over WiFi
- [ ] nRF5340+nRF7002 thin client streams audio to gateway over WiFi

### Phase 3 (Alif E7 "Edge" board)
- [ ] Custom PCB: E7 + 64MB PSRAM + nRF module + audio + LiPo
- [ ] Boots, PicoClaw gateway starts, WiFi connects
- [ ] Battery operation validated (measure current, estimate life)
- [ ] Ethos-U55 runs wake word detection on M55

### Phase 4 (RK3576 "Pro" board)
- [ ] Yocto image boots on Radxa ROCK 4D
- [ ] Full OpenClaw gateway runs, WS on port 18789
- [ ] RKNN-LLM runs TinyLlama 1.1B locally
- [ ] Custom carrier board powers on, audio + M.2 + OLED functional
