# Phase 5: ELF Size Analysis

Status: Planned

## Problem

No ROM/RAM tracking. Can't catch bloat before it ships.

## Deliverables

1. **`analyze_elf` tool** — Parse ELF sections, report flash/RAM usage by module
2. **`compare_sizes` tool** — Diff two builds to show what grew/shrank
3. **Size tracking in CI** — Report size delta on every PR
