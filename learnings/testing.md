# Learnings: Testing on macOS

### native_sim is Linux-only
The POSIX architecture (`native_sim`, `native_posix`) doesn't work on macOS. Use `qemu_cortex_m3` for unit tests that need an ARM target.

### Flash-dependent code can't run on QEMU
`CONFIG_DEBUG_COREDUMP_BACKEND_FLASH_PARTITION` requires `FLASH_HAS_DRIVER_ENABLED` which QEMU doesn't provide. For tests that need flash, use `build_only: true` with `platform_allow` for real boards, or find an alternative test strategy.

### Shell dummy backend for testing
`CONFIG_SHELL_BACKEND_DUMMY=y` works well for testing shell commands without hardware. Pattern:
```c
const struct shell *sh = shell_backend_dummy_get_ptr();
shell_execute_cmd(sh, "board info");
const char *output = shell_backend_dummy_get_output(sh, &size);
zassert_not_null(strstr(output, "Board:"), "expected Board: in output");
```

### shell_execute_cmd returns 1 = help printed
When a shell command has a NULL handler (parent with subcommands only), the shell prints subcommand help and returns `SHELL_CMD_HELP_PRINTED` (1), not 0. Tests must call the full subcommand path (e.g., `"board info"` not `"board"`).

### Twister needs Zephyr SDK env vars
MCP server subprocesses don't inherit shell profile env vars. Twister requires `ZEPHYR_TOOLCHAIN_VARIANT` and `ZEPHYR_SDK_INSTALL_DIR` to be set. The `zephyr-build` MCP auto-detects the SDK from `~/.cmake/packages/Zephyr-sdk/` (registered by `setup.sh`). If auto-detection fails, set these env vars in the MCP server's launch environment.
