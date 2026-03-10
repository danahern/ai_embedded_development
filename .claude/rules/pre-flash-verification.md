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

### Post-Yocto-Build DTB Check (MANDATORY — do this before staging)

When a DTB comes from a Yocto build (not manual dtc compilation), the Yocto DCT tool
(`dct-kernel.bbclass`, `do_dct_to_dts` task) modifies the kernel header file
`devkit_ex_dct_defines.h` in-place based on machine variables. This is a stateful
side-effect: the header persists between builds. If `HYPRAM_ONLY` evaluates to `''`
(empty string), neither the `'1'` nor `'0'` branch fires — the header is NOT updated
and retains contaminated state from the prior build.

**After ANY Yocto build that produces a DTB for Alif E7**:
1. Verify `HYPRAM_ONLY = "1"` is set explicitly in the machine config (not computed)
2. Decompile the DTB immediately after the build completes:
   `dtc -I dtb -O dts <output.dtb> | grep -A3 "memory@a0000000"`
3. Confirm `status = "okay"` and `reg = <0xa0000000 0x2000000>` (32MB)
4. If HyperRAM is disabled: DO NOT STAGE. Fix the machine config and rebuild.

Do NOT rely on "build succeeded" as evidence of correct DTB content. These are independent.

### DTB Verification (BLOCKING — do this BEFORE gen_toc)
1. Decompile DTB with `dtc -I dtb -O dts` and verify:
   - All nodes that should be enabled show `status = "okay"`
   - All nodes that should be disabled show `status = "disabled"`
   - `chosen/bootargs` contains expected parameters (earlycon, console, root, etc.)
   - `aliases` point to correct nodes (e.g., serial0 → correct UART)
   - Memory nodes have correct addresses and sizes
2. Compare DTB content against the DTS source fixes — every fix must be reflected
3. **MANDATORY diff against known-working DTB**: Decompile BOTH the new DTB and the last known-working DTB, diff them, and review every difference. Known-working DTB: `tools/setools/build/images/devkit-e7-ospi.dtb.bin` (md5 `caea9c2cc0cda2ce3983647619972219`). If no known-working DTB exists, triple-check all memory nodes and bootargs manually.
4. **Memory nodes checklist** (E7-specific):
   - `memory1@2000000` (SRAM): status "okay", reg 0x2000000 0x7de000
   - `memory@a0000000` (HyperRAM): status **"okay"**, reg 0xa0000000 **0x2000000** (32MB, NOT 64MB)
   - `memory2@2000000` (combined): status "disabled"
   - If HyperRAM is disabled, the kernel WILL NOT BOOT (only ~8MB SRAM available)

### Kernel Verification
1. Verify `.config` contains all required CONFIG options
2. Verify `xipImage` or `vmlinux` symbols match expectations (e.g., `__log_buf` address)
3. If kernel config changed, verify the new binary was actually rebuilt (check timestamps, md5)

### TF-A Verification (BLOCKING — wrong TF-A = silent kernel death)
1. **Always build fresh** — run `firmware/linux/alif-e7/build-tfa.sh` (~5 sec). Never use stale prebuilt copies.
2. Verify `strings bl32-ospi.bin | grep "USB clocks enabled"` — MUST be present
3. Verify size is ~30KB (not ~26KB — missing `ENABLE_STACK_PROTECTOR=strong` produces smaller binary)
4. Without USB clock enabling, TF-A boots fine but kernel silently fails (no earlycon, no crash output)
5. The build script verifies all of this automatically

### Artifact Pipeline Verification
1. Verify the file being flashed matches the build output (md5sum comparison)
2. Verify the flash config (JSON) references the correct filenames
3. Verify all referenced binaries exist in the staging directory
4. **Check md5 against the known-working manifest in MEMORY.md** — every artifact has a recorded md5

### After Flash
1. Read back key memory locations via JLink to confirm data was written
2. Verify FDT magic (0xD00DFEED) at DTB MRAM address
3. Verify first bytes of kernel match expected binary

## MCP-First During Debugging

Any JLink operation during debugging (read memory, reset, halt) MUST use the `embedded-probe` MCP.
Do NOT use Bash JLinkExe directly. If embedded-probe is not loaded (it is a deferred tool), load it:

  ToolSearch: "select:mcp__embedded-probe__connect"

Then use the appropriate tool (connect, read_memory, reset, etc.). Using Bash JLinkExe violates
MCP-first policy and bypasses logging. This has occurred multiple times — be explicit about loading
the deferred tool before any JLink operation.

**If you believe embedded-probe is incapable of the operation** (e.g., "probe-rs doesn't support Cortex-A32"):

You are likely WRONG. Do these checks before resorting to Bash:
1. Call `list_targets` — it lists known chip names including Cortex-A targets with their backend type
2. Attempt `connect()` anyway — connect() auto-falls-back to JLinkExe for any chip probe-rs rejects
3. Read `claude-mcps/embedded-probe/CLAUDE.md` fully, especially the "JLink Auto-Fallback Backend" section
4. Check `MEMORY.md` for notes on the target chip

The embedded-probe CLAUDE.md header says "Cortex-M, RISC-V, Xtensa" — this describes the probe-rs
primary path only. The JLink fallback backend covers ANY chip in Segger's device DB, including all
Cortex-A targets. "Probe-rs doesn't support it" does NOT mean "embedded-probe can't do it."

See `retrospective/embedded-probe-jlink-backend-missed.md`.

## Rationale
Each flash cycle costs 5-15 minutes. Flashing wrong/stale artifacts wastes that time and creates confusing debug state. Verification takes seconds. Always verify before committing to a flash. The DTB verification rule was written after the setools-path-confusion incident and violated within 24 hours (dtb-verification-skip incident) — advisory text is not sufficient. Treat these as blocking gates.
