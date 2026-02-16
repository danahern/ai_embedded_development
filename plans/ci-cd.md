# CI/CD Pipeline — Phase 1 (Solo)

Status: Complete
Created: 2026-02-14
Updated: 2026-02-15

## Problem

No automated quality gates. Code pushed with no build verification, no test runs, no consistency checks. At scale this becomes 300 engineers pushing unverified firmware. Need to start building CI now so pipeline shapes are proven before the team grows.

## Approach

GitHub Actions with a hybrid runner strategy. Three per-repo workflows covering all testable code. Two runner targets:

- **Hosted runners** (`ubuntu-latest`) — ensures workflows work in clean environments, validates portability
- **Self-hosted runner** on `danahern-pc` (i9-9900K, 64GB RAM, WSL2) — faster builds via local cache, and hardware-in-the-loop testing with boards plugged in via USB

Same workflow YAML runs on both — runner labels control routing. This proves the full pipeline (build → QEMU test → flash → BLE verify) from day one instead of deferring hardware testing to Phase 3.

Full scale roadmap (300 engineers, BuildKite, board farm): `~/.claude/plans/ci-infrastructure-at-scale.md`

## Solution

### Workflow 1: claude-mcps (Rust + Python MCP servers)

**Trigger:** push to any branch
**Runner:** ubuntu-latest
**What it tests:**

| Server | Type | Test command |
|--------|------|-------------|
| zephyr-build | Rust | `cargo test` |
| embedded-probe | Rust | `cargo test` |
| elf-analysis | Rust | `cargo test` |
| esp-idf-build | Rust | `cargo test` |
| knowledge-server | Rust | `cargo test` |
| saleae-logic | Python | `pytest tests/` |
| hw-test-runner | Python | `pytest tests/` |

**Caching:** `actions/cache` on `~/.cargo/registry`, `~/.cargo/git`, and each server's `target/` dir. Key on `Cargo.lock` hash. Without cache: ~5 min. With cache: ~1 min.

**Structure:** Single workflow, two jobs (Rust + Python) running in parallel.

### Workflow 2: zephyr-apps (Zephyr library tests)

**Trigger:** push to any branch
**Runner:** ubuntu-latest
**Container:** `ghcr.io/zephyrproject-rtos/ci:v0.27.4` (pre-installed SDK + QEMU)
**What it tests:**

| Suite | Platform | Tests |
|-------|----------|-------|
| libraries.crash_log | qemu_cortex_m3 | 4 |
| libraries.device_shell | qemu_cortex_m3 | 3 |
| libraries.eai_osal | qemu_cortex_m3 | 44 |
| libraries.wifi_prov | qemu_cortex_m3 | 22 |

**Command:** `python3 zephyr/scripts/twister -T lib -p qemu_cortex_m3`

**Caching:** `actions/cache` on west modules (`~/.west`, `bootloader/`, `modules/`, `tools/`). Key on `west.yml` hash. First run: ~10-15 min (west update). Cached: ~2-3 min (just twister).

**Optional job: build-only smoke test** for each app × board. Catches Kconfig errors and link failures without hardware. Run `west build` with no flash.

### Workflow 3: test-tools (Python test utilities)

**Trigger:** push to any branch
**Runner:** ubuntu-latest
**Command:** `pytest tests/`
**Simple — no caching needed, runs in seconds.**

### Workflow 4: workspace integration (optional, later)

**Trigger:** push to main
**What:** Checks submodule consistency — ensures workspace root's submodule refs point to commits that pass their own CI. Prevents "green submodule, broken integration" scenarios.

### Workflow 5: Hardware-in-the-loop (self-hosted runner on danahern-pc)

**Trigger:** push to main, or manual dispatch
**Runner:** self-hosted (labeled `hw-test`)
**What it tests:**

| Step | Tool | What |
|------|------|------|
| Build firmware | west build (local) | Compile for real board targets |
| Flash | probe-rs / nrfjprog via usbipd | Program boards over USB |
| Boot validate | RTT pattern match | Verify "Booting Zephyr" appears |
| BLE discover | hw-test-runner | Verify device advertises |
| Functional test | hw-test-runner | NUS echo, WiFi provision, TCP throughput |

**Depends on:** WSL2 setup on danahern-pc with usbipd-win for USB passthrough, GitHub Actions self-hosted runner agent installed.

**Not blocking for merge** — runs post-merge or on manual trigger. Too slow and hardware-dependent to gate every PR.

### Self-hosted runner setup (danahern-pc)

Prerequisites on Windows:
1. WSL2 with Ubuntu 24.04
2. `usbipd-win` installed for USB device passthrough to WSL2
3. Docker Desktop with WSL2 backend (optional, for containerized builds)

Inside WSL2:
1. Zephyr SDK + west workspace initialized
2. Rust toolchain (for MCP server tests)
3. Python 3.x + pytest
4. probe-rs CLI
5. GitHub Actions self-hosted runner agent (`./run.sh` as systemd service)
6. Runner labels: `self-hosted`, `linux`, `hw-test`

USB devices attached via usbipd:
- J-Link / nRF DKs (for probe-rs flash + RTT)
- ESP32 USB serial (for esptool flash + monitor)

## Implementation

### Files to create

| File | Purpose |
|------|---------|
| `claude-mcps/.github/workflows/test.yml` | Rust cargo test + Python pytest |
| `zephyr-apps/.github/workflows/test.yml` | Twister on QEMU + optional build smoke test |
| `test-tools/.github/workflows/test.yml` | pytest |

### Implementation order

1. `claude-mcps` workflow — highest value, fastest to implement, no special deps
2. `test-tools` workflow — trivial, do alongside #1
3. `zephyr-apps` workflow — needs Zephyr Docker image + west caching, more complex
4. Self-hosted runner on danahern-pc — WSL2 setup, usbipd, runner agent, toolchain install
5. Hardware-in-the-loop workflow — flash + boot + BLE verify on self-hosted runner
6. Branch protection rules — require CI pass before merge (after workflows are stable)

### Key decisions

- **Zephyr container version:** Pin to specific tag (`v0.28.7`), not `latest`. Reproducibility matters.
- **West manifest caching:** Cache the entire west workspace keyed on `west.yml` hash. Invalidate on manifest changes.
- **Build smoke test scope:** Start with qemu_cortex_m3 only (works without hardware). Add real board targets later when we have cross-compilation verified.
- **No hardware tests in Phase 1.** QEMU-based twister tests only.
- **Two-phase build/test split:** Docker produces deterministic build artifacts (ELF/HEX). Hardware operations (flash, BLE test, RTT) stay native via MCP tools. The artifact is the contract between phases.

### Local Docker builds (Makefile)

`zephyr-apps/Makefile` wraps Docker-based builds using the same CI container:

```bash
make build APP=crash_debug BOARD=nrf54l15dk/nrf54l15/cpuapp  # Docker west build
make test                                                      # Docker twister on QEMU
make shell                                                     # Interactive container
```

Artifacts land in `apps/<app>/build/<board>/zephyr/zephyr.{elf,hex}` — same path as MCP-driven builds. Flash with probe-rs/nrfjprog natively.

Benefits:
- Same SDK/toolchain as CI → bit-for-bit reproducible binaries
- No local Zephyr SDK needed for build-only workflows (still needed for MCP-driven iteration)
- At scale: engineers build in Docker, hardware farm tests the artifacts

## Verification

- [x] `claude-mcps` workflow runs on push and all Rust + Python tests pass
- [x] `zephyr-apps` workflow runs twister successfully in Docker container
- [x] `test-tools` workflow runs pytest successfully
- [x] Cargo cache hit on second run (knowledge-server 54s→21s, others were already fast)
- [x] West module cache hit on second run (no re-download, 5m12s — compile time dominates)
- [x] Self-hosted runner on danahern-pc picks up jobs (test workflow run 22075803196 passed)
- [x] USB passthrough works: probe-rs sees J-Link (1366:1051) from WSL2 via usbipd
- [x] Hardware workflow: build → flash → boot validate succeeds on self-hosted runner (run 22077271838, 1m24s)
- [x] Branch protection enabled on main requiring CI pass (claude-mcps, zephyr-apps, test-tools)

## Modifications

- Updated 2026-02-15: Expanded from initial sketch to full Phase 1 plan. Full scale strategy (300 engineers, BuildKite, hardware lab, board farm) documented separately in `~/.claude/plans/ci-infrastructure-at-scale.md`.
- Updated 2026-02-15: Added danahern-pc (i9-9900K, 64GB, Win11 Pro) as self-hosted runner. Hybrid approach — hosted runners for clean-env validation + self-hosted for fast builds and hardware-in-the-loop. Collapses Phase 1-3 for solo dev.
- Updated 2026-02-15: All 3 workflows created and pushed. claude-mcps (7 jobs) and test-tools passing green. zephyr-apps workflow pushed, awaiting first run. Used Zephyr CI container v0.28.7 with west module caching.
- Updated 2026-02-16: Fixed zephyr-apps CI — crash_log and device_shell test CMakeLists had redundant ZEPHYR_EXTRA_MODULES (already auto-discovered via workspace module.yml). Added Docker build Makefile for local reproducible builds.
- Updated 2026-02-16: Implemented hardware-in-the-loop CI workflow (`.github/workflows/hw-test.yml`). Tests hello_world and osal_demo on nRF5340 DK via self-hosted runner. Uses persistent west workspace (`~/ci-workspace/`) with hash-check on `west.yml` to avoid re-syncing modules. Flashes `.hex` via `probe-rs download`, reads RTT via `probe-rs attach` with ELF for symbol lookup. Added RTT board overlay for hello_world (`boards/nrf5340dk_nrf5340_cpuapp.conf`). Not merge-blocking — triggers on push to main + workflow_dispatch.
