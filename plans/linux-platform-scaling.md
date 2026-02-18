# Linux Platform Scaling

Status: Complete
Created: 2026-02-17

## Problem

The linux-build MCP was the youngest server (759 LOC, 9 tools, SSH-only transport). Recent STM32MP1 work added ADB USB gadget and Yocto custom builds, but the tooling hadn't caught up:

- **meta-eai was trapped in a Docker volume** — not version-controlled, can't be reviewed or shared
- **ADB was available but not in any MCP** — shell, file transfer, pull all required manual CLI
- **No flash tool** — flashing WIC images was a shell script
- **Yocto builds were black-box `docker exec`** — no progress tracking, no background support
- **Transport details repeated on every call** — board_ip/serial passed to each tool individually

## Approach

Five phased improvements, each independently implementable:

| Phase | What | New Tools |
|-------|------|-----------|
| P0 | Extract meta-eai to git | 0 (modifies start_container) |
| P1 | ADB transport | adb_shell, adb_deploy, adb_pull |
| P2 | Flash image tool | flash_image |
| P3 | Yocto build awareness | yocto_build, yocto_build_status |
| P4 | Board connection model | board_connect, board_disconnect, board_status |

Implementation order: P0 → P1 → P3 → P2 → P4

## Solution

### P0: meta-eai extracted to `firmware/linux/yocto/meta-eai/`
All 9 recipe files extracted from Docker volume to git. `start_container` gained `extra_volumes` parameter for bind-mounting the layer back into containers.

### P1: ADB transport via `adb_client.rs`
New module parallel to SSH functions in `docker_client.rs`. Three tools: `adb_shell`, `adb_deploy`, `adb_pull`. Config gains `--adb-serial` / `default_adb_serial`.

### P2: Flash image via piped `bzcat | dd`
`flash_image` tool supports SSH and ADB transports. Uses `spawn_blocking` with `std::process::Command` for piping (Tokio's ChildStdout doesn't impl Into<Stdio>).

### P3: Background Yocto builds
`yocto_build` constructs bitbake command with env sourcing, optional `cleansstate`. Background mode uses `tokio::spawn` + `Arc<RwLock<HashMap>>` for state tracking. Output truncated to first 20 + last 80 lines.

### P4: Board connection model
`board_connect` stores transport details (SSH or ADB), returns `board_id`. Auto mode tries ADB devices first, falls back to SSH. `board_status` lists all connections or checks one.

**Final tool count:** 9 existing + 8 new = 17 tools (originally planned as 18, but `board_status` covers both single and list-all, so `board_list` was unnecessary).

## Implementation Notes

### Files Created
- `claude-mcps/linux-build/src/adb_client.rs` — ADB CLI wrapper (shell/push/pull/devices/flash)
- `firmware/linux/yocto/meta-eai/` — 9 Yocto recipe files extracted from Docker volume

### Files Modified
- `claude-mcps/linux-build/src/lib.rs` — added `pub mod adb_client`
- `claude-mcps/linux-build/src/config.rs` — added `adb_serial` to Args/Config
- `claude-mcps/linux-build/src/docker_client.rs` — `extra_volumes` param, `flash_image_ssh()`
- `claude-mcps/linux-build/src/tools/types.rs` — 9 new arg structs (all phases)
- `claude-mcps/linux-build/src/tools/linux_build_tools.rs` — complete rewrite: state types, 8 new tools, 29 unit tests
- `claude-mcps/linux-build/CLAUDE.md` — updated tool listings
- `claude-mcps/linux-build/README.md` — updated tool table, examples, CLI flags
- `CLAUDE.md` — updated linux-build MCP section with all 17 tools

### Key Decisions
- **spawn_blocking for flash piping**: Tokio's `ChildStdout` can't convert to `std::process::Stdio`, so flash image uses `tokio::task::spawn_blocking` with std process commands for the bzcat→ssh/adb pipeline.
- **All types defined upfront**: Added all arg structs to `types.rs` in one pass rather than per-phase, since they don't depend on each other.
- **TOOL_COUNT const**: Used a constant rather than counting at runtime, matching the pattern from other MCP servers.
- **No board_id on existing tools yet**: The plan called for adding `board_id` to existing tools like `deploy` and `ssh_command`, but this was deferred to keep the diff focused. Board connections work standalone; integration with existing tools can follow.

## Modifications

- **board_id on existing tools deferred**: Plan called for adding `board_id` to `deploy`, `ssh_command`, `adb_shell`, etc. Deferred to avoid touching every existing tool's args and validation in this pass.
- **17 tools instead of 18**: `board_status` handles both single-board and list-all cases, so separate `board_list` was unnecessary.
- **LOC came in at ~900 as estimated**: `linux_build_tools.rs` grew from 398 to 1182 lines, `adb_client.rs` added 140 lines.
