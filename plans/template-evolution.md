# Template Evolution

Status: Ideation
Created: 2026-02-14

## Problem

As the workspace grows, apps will share common patterns beyond the core template (e.g., core+ble, core+sensor). Manually noticing these patterns and creating templates is tedious and easy to miss.

## Deliverables

1. **Pattern detection skill or tool**
   - Analyzes `apps/` for common CMake/conf/code patterns beyond the core template
   - Diffs existing apps against the core template to identify repeated additions
   - Reports: "3 apps add BLE NUS with the same prj.conf entries and main.c boilerplate"

2. **Template suggestion mechanism**
   - When patterns are detected, suggests new template variations
   - E.g., "core+ble" = core template + BT config + NUS init + advertising boilerplate
   - User approves, tool generates the template constants for `templates.rs`

3. **Template registry**
   - Templates declared in a manifest (not just hardcoded Rust constants)
   - `create_app` reads available templates dynamically
   - Makes it easy to add/modify templates without rebuilding the MCP server

## Open Questions

- Should this be a Claude skill (`/check-templates`) or an MCP tool (`suggest_templates`)?
- Should template definitions live in YAML files alongside the apps, or stay as Rust constants?
- How often should pattern detection run — on demand, or automatically after `create_app`?

## Dependencies

- Scaffolding plan must be complete — provides the core template and manifest system
