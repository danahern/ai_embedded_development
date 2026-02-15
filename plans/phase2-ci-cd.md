# Phase 2: CI/CD Pipeline

Status: Planned (after Phase 1)

## Problem

No automated quality gates. 50 engineers pushing code with no build verification.

## Approach

GitHub Actions workflow that runs on every PR:
1. Build all apps for each target board (`build_all`)
2. Run twister tests on QEMU (no hardware needed)
3. Report results as PR check

## Key Decisions (TBD)

- Self-hosted runners (need Zephyr SDK + west) vs. Docker container
- Which boards to build for (all vs. subset)
- Hardware-in-the-loop tests (requires self-hosted runner with probe)
- Build caching strategy (ccache, Zephyr module cache)

## Workflow Sketch

```yaml
name: Build & Test
on: [pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    container: zephyrproject/ci:latest
    steps:
      - west init && west update
      - west build -b qemu_cortex_m3 apps/crash_debug
      - twister -T lib -p qemu_cortex_m3
```
