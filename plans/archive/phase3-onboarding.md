# Phase 3: Onboarding Automation

Status: Planned

## Problem

- `.mcp.json` has hardcoded absolute paths (not portable)
- No "first task" verification after setup
- No dependency audit tool
- Engineers can't validate setup succeeded

## Deliverables

1. **Portable `.mcp.json` generation** — `setup.sh` already does this; ensure it uses `$PWD` and works for any engineer
2. **Onboarding checklist** in README.md — Clear success criteria after setup
3. **`check-dependencies.sh`** — Validates each subsystem is complete and compatible
4. **Quickstart guide** — "Build and flash your first app in 5 minutes"
5. **Document `.claude/settings.local.json`** — What it does, how to extend
