# Phase 4: Project Scaffolding

Status: Planned

## Problem

Creating a new Zephyr app is manual copy-paste. At 25 projects, consistency matters.

## Deliverables

1. **`create_app` tool** (in zephyr-build MCP or as a skill)
   - Generates app skeleton: CMakeLists.txt, prj.conf, src/main.c
   - Supports templates: bare, ble_peripheral, sensor, shell_only
   - Auto-includes selected libraries
   - Sets up board overlays

2. **App manifest** (`manifest.yml` per app)
   - Declares target boards, library dependencies, config options
   - Enables auto-generation of CMakeLists boilerplate
   - Feeds into build matrix and CI

3. **Library dependency declarations**
   - Explicit deps between libraries
   - Auto-include transitive Kconfig overlays
