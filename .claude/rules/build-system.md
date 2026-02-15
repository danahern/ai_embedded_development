---
paths: ["**/CMakeLists.txt", "**/*.cmake", "**/module.yml", "**/Kconfig*"]
---
# Build System Learnings

- **module.yml paths are relative to module root** — parent of `zephyr/`, not relative to yml file. Use `cmake: .` not `cmake: ..`.
- **Board qualifiers: `/` in CMake, `_` in filenames** — `nrf52840dk/nrf52840` in CMake, `nrf52840dk_nrf52840.overlay` for files. Let Zephyr auto-discover from `boards/`.
- **OVERLAY_CONFIG vs DTC_OVERLAY_FILE** — `.conf` files use `OVERLAY_CONFIG`, `.overlay` files use `DTC_OVERLAY_FILE`. Zephyr auto-discovers DTS from `boards/`.
- **Don't duplicate board overlays** — library overlays in `boards/` are included via CMakeLists.txt. Don't copy to app's `boards/`.
- **Use module.yml for shared library auto-discovery** — repo root `zephyr/module.yml` pointing to `lib/CMakeLists.txt` eliminates `ZEPHYR_EXTRA_MODULES` boilerplate.
