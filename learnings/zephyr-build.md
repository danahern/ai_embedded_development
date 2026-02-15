# Learnings: Zephyr Build System

### module.yml paths are relative to module root, not the yml file
`zephyr/module.yml` paths (`cmake:`, `kconfig:`) resolve relative to the module root (the parent of `zephyr/`), not relative to `module.yml` itself. Use `cmake: .` and `kconfig: Kconfig`, not `cmake: ..` / `kconfig: ../Kconfig`.

### Board qualifiers: `/` in CMake, `_` in filenames
`${BOARD}` expands to `nrf52840dk/nrf52840` (with `/`) but DTS overlay files use `_` separator: `nrf52840dk_nrf52840.overlay`. Don't set `DTC_OVERLAY_FILE` manually — put overlays in the app's `boards/` directory and let Zephyr auto-discover them.

### Shell command name conflicts
Zephyr has a built-in `device` shell command (`subsys/shell/modules/device_service.c` with subcommands `list` and `init`). Custom shell commands must pick unique names. We renamed ours to `board` after debugging why `shell_execute_cmd(sh, "device info")` returned 1 instead of 0 — it was dispatching to Zephyr's built-in, not ours.

### RTT buffer conflicts
`CONFIG_LOG_BACKEND_RTT` and `CONFIG_SHELL_BACKEND_RTT` both default to buffer 0. When using both, set `CONFIG_SHELL_BACKEND_RTT_BUFFER=1` or the build fails with "Conflicting log RTT backend enabled on the same channel."

### OVERLAY_CONFIG vs DTC_OVERLAY_FILE
`OVERLAY_CONFIG` is for Kconfig fragments (`.conf` files). `DTC_OVERLAY_FILE` is for devicetree overlays (`.overlay` files). Zephyr auto-discovers DTS overlays from `boards/` but you must explicitly list Kconfig overlays via `OVERLAY_CONFIG`.
