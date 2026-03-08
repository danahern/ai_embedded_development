# Pre-Flash Verification Rule

**MANDATORY: Never flash without verifying the artifact matches expectations.**

## Before ANY flash operation, verify:

### Staging Directory Verification (check FIRST)

The alif-flash MCP reads from `tools/setools/build/` — NOT `firmware/linux/alif-e7/setools/build/`.
Claude Desktop spawns MCP processes from the workspace root, so `--setools-dir ./tools/setools`
resolves to `<workspace-root>/tools/setools/` regardless of the `cwd` field in `.mcp.json`.

1. Confirm the artifact destination is `tools/setools/build/images/` (absolute: `/Users/danahern/code/claude/work/tools/setools/build/images/`)
2. Verify md5 of artifact in that directory matches the build output — not just that a file exists
3. After copying any artifact, run `gen_toc` again — `AppTocPackage.bin` must be regenerated to reflect the new image
4. Check `/tmp/alif-flash.log` first line after server start for the resolved setools_dir path

**Do NOT stage artifacts to `firmware/linux/alif-e7/setools/build/` — the MCP never reads from there.**

### DTB Verification
1. Decompile DTB with `dtc -I dtb -O dts` and verify:
   - All nodes that should be enabled show `status = "okay"`
   - All nodes that should be disabled show `status = "disabled"`
   - `chosen/bootargs` contains expected parameters (earlycon, console, root, etc.)
   - `aliases` point to correct nodes (e.g., serial0 → correct UART)
   - Memory nodes have correct addresses and sizes
2. Compare DTB content against the DTS source fixes — every fix must be reflected

### Kernel Verification
1. Verify `.config` contains all required CONFIG options
2. Verify `xipImage` or `vmlinux` symbols match expectations (e.g., `__log_buf` address)
3. If kernel config changed, verify the new binary was actually rebuilt (check timestamps, md5)

### Artifact Pipeline Verification
1. Verify the file being flashed matches the build output (md5sum comparison)
2. Verify the flash config (JSON) references the correct filenames
3. Verify all referenced binaries exist in the staging directory

### After Flash
1. Read back key memory locations via JLink to confirm data was written
2. Verify FDT magic (0xD00DFEED) at DTB MRAM address
3. Verify first bytes of kernel match expected binary

## Rationale
Each flash cycle costs 5-15 minutes. Flashing wrong/stale artifacts wastes that time and creates confusing debug state. Verification takes seconds. Always verify before committing to a flash.
