# CI/CD Pipeline — Phase 1 (Solo)

Status: Planned
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

- **Zephyr container version:** Pin to specific tag (e.g., `v0.27.4`), not `latest`. Reproducibility matters.
- **West manifest caching:** Cache the entire west workspace keyed on `west.yml` hash. Invalidate on manifest changes.
- **Build smoke test scope:** Start with qemu_cortex_m3 only (works without hardware). Add real board targets later when we have cross-compilation verified.
- **No hardware tests in Phase 1.** QEMU-based twister tests only.

## Verification

- [ ] `claude-mcps` workflow runs on push and all Rust + Python tests pass
- [ ] `zephyr-apps` workflow runs twister successfully in Docker container
- [ ] `test-tools` workflow runs pytest successfully
- [ ] Cargo cache hit on second run (build time < 1 min)
- [ ] West module cache hit on second run (twister start < 3 min)
- [ ] Self-hosted runner on danahern-pc picks up jobs (WSL2 + runner agent working)
- [ ] USB passthrough works: probe-rs can see J-Link from WSL2 via usbipd
- [ ] Hardware workflow: build → flash → boot validate succeeds on self-hosted runner
- [ ] Branch protection enabled on main requiring CI pass

## Modifications

- Updated 2026-02-15: Expanded from initial sketch to full Phase 1 plan. Full scale strategy (300 engineers, BuildKite, hardware lab, board farm) documented separately in `~/.claude/plans/ci-infrastructure-at-scale.md`.
- Updated 2026-02-15: Added danahern-pc (i9-9900K, 64GB, Win11 Pro) as self-hosted runner. Hybrid approach — hosted runners for clean-env validation + self-hosted for fast builds and hardware-in-the-loop. Collapses Phase 1-3 for solo dev.
