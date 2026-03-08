# Retrospective: setools Directory Confusion

**Date:** 2026-03-08
**Severity:** High — approximately 6 wasted flash sessions (each 7-15 minutes) and one full debugging day
**Status:** Resolved — correct path identified and documented

---

## Incident Summary

Across multiple sessions (2026-03-06 22:51 through 2026-03-07 19:49), the alif-flash MCP server was correctly reading from `tools/setools/build/images/` to flash artifacts — but session work was being staged into `firmware/linux/alif-e7/setools/build/images/`, a completely different directory that the MCP never reads. The result was that DTB fixes written in one place were never seen by the tool that flashed the board. Every flash cycle pushed the old, unfixed DTB to MRAM, and the kernel continued to fail with "no ATAGS support" or silent console because the broken DTB it had been given contained the wrong UART alias and a disabled HyperRAM node.

The log evidence shows 25 log lines representing approximately 6 complete flash operations with the old 31920-byte DTB before the correct staging directory was discovered. The fix was eventually discovered by tracing the MCP's actual setools_dir at runtime, but only after significant debugging time had been spent.

---

## Timeline

| Time | Event |
|------|-------|
| 2026-03-06 21:35 | alif-flash MCP server starts (first session). setools_dir = `./tools/setools`, process cwd = workspace root. |
| 2026-03-06 22:51 | First flash including `appkit-e7-ospi.dtb` (31905 bytes, address 0x80010000). DTB from `tools/setools/build/images/` — unfixed, wrong address in config. |
| 2026-03-06 23:00 | Second flash with same stale DTB. Kernel reports "no ATAGS support". |
| 2026-03-07 08:18 | Third session. DTS fixes have been applied and kernel rebuilt. DTB is copied to `firmware/linux/alif-e7/setools/build/images/appkit-e7-ospi.dtb`. Same stale 31905-byte DTB is flashed from `tools/setools/`. |
| 2026-03-07 08:26 | Fourth flash — identical result. Kernel still fails. |
| 2026-03-07 09:23 | Fifth flash — still 31920 bytes, still wrong. Config address changed to 0x80200000 in `firmware/linux/alif-e7/setools/build/config/` but the MCP reads config from `tools/setools/build/config/`, which has not been updated. |
| 2026-03-07 09:40 | Sixth flash — address is now 0x80200000 (correct). DTB is still 31920 bytes (stale, unfixed). |
| 2026-03-07 09:54 | Seventh and eighth flashes — still stale DTB. "No ATAGS" persists. |
| 2026-03-07 20:59 | DTB size jumps to 33760 bytes — first flash with the fixed DTB in the correct directory. |
| 2026-03-07 22:28 | Log shows `AppTocPackage.bin not found at /firmware/linux/alif-e7/AppTocPackage.bin` — a flash call was made with a config path from the wrong directory, confirming both directories were still being confused. |
| 2026-03-08 00:15 | Both directories now contain the same 33696-byte DTB (690c979f...). Directories in sync. |

---

## Root Cause Analysis

```
Symptom: Kernel crashes with "no ATAGS support" after multiple flash-and-test cycles
  <- DTB on board does not contain our UART alias or earlycon fixes
    <- gen_toc and flash read from tools/setools/build/images/
      <- DTB was staged to firmware/linux/alif-e7/setools/build/images/ (different directory)
        <- No documentation specified which directory the MCP uses
          <- The .mcp.json cwd: "./claude-mcps/alif-flash" is misleading — it is NOT used
             as the base for resolving --setools-dir (Claude Desktop spawns from workspace root)
            <- Two structurally identical setools directories exist without explanation
              <- The firmware/linux/alif-e7/ directory is where Alif's upstream setools
                 release was originally unpacked, before the workspace tools/ dir was set up
                <- No MEMORY.md or rules entry captured which directory the MCP actually uses
```

**Proximate cause:** DTB and config edits were staged to `firmware/linux/alif-e7/setools/build/`, which the MCP never touches.

**Contributing factors:**

- The `.mcp.json` entry has `"cwd": "./claude-mcps/alif-flash"`, which implies the MCP's working directory is `claude-mcps/alif-flash/`. A reader would naturally infer that `--setools-dir ./tools/setools` resolves relative to that cwd, putting the setools directory at `claude-mcps/alif-flash/tools/setools/` (which does not exist). In reality, Claude Desktop spawns all MCP processes from the workspace root, making `./tools/setools` resolve to the workspace-level `tools/setools/`. This is non-obvious and undocumented.

- Two directories share nearly identical structure (`build/config/`, `build/images/`). The firmware-level one is the upstream Alif setools release location; the workspace-level one is the MCP's actual working directory. Nothing distinguishes them at a glance.

- The `uart-console-bringup.md` plan explicitly listed config paths under `firmware/linux/alif-e7/setools/build/config/`, reinforcing the wrong mental model.

- The pre-flash verification rule in `.claude/rules/pre-flash-verification.md` checks artifact content (md5, dtc decompile) but does not specify which directory the MCP actually uses. A correct md5 match between a freshly built DTB and the wrong staging directory would satisfy the rule while still flashing stale data.

- The log file at `/tmp/alif-flash.log` contained the evidence — the `AppTocPackage.bin not found` warning showed an absolute path into `firmware/linux/alif-e7/` — but the log was not consulted during the failing sessions.

**Systemic root cause:** No persistent record (MEMORY.md, rules file, plan comment) captured the resolved path of the MCP's setools_dir. This is a knowledge capture failure: the correct path was discoverable from `.mcp.json` analysis, but that analysis was never done and its conclusion was never recorded.

---

## Impact Assessment

**Direct impact:**
- Approximately 6 complete flash cycles with a stale DTB, each lasting 7-15 minutes = 42-90 minutes of hardware time wasted.
- Multiple debugging sessions investigating "no ATAGS support" where the root cause was a staging directory mismatch rather than any code or configuration error.
- The `uart-console-bringup.md` plan listed incorrect paths, further reinforcing the wrong directory in future sessions.

**Near-misses:**
- The MCP's `gen_toc` call at one point returned `FileNotFoundError: './tools/setools/test-tfa-dtb-200000.json'` (log line 860). This error was a clear signal that the process cwd is the workspace root and the setools_dir is `./tools/setools` — but the error was treated as a config path problem rather than evidence about path resolution.
- The `AppTocPackage.bin not found at /firmware/linux/alif-e7/AppTocPackage.bin` warning (log lines 1087, 1108) explicitly showed an absolute path into the wrong directory. This too was not caught in time to prevent additional bad flashes.

**Blast radius:** Any future session that needs to copy artifacts for flashing is at risk of the same mistake if the correct staging path is not prominently documented. This includes kernel images, rootfs, TF-A binaries — anything that needs to land in `tools/setools/build/images/`.

**Severity:** High. Multiple hours of debugging time lost. Hardware cycling was wasted, and the failure mode (board boots with wrong DTB) produces confusing symptoms that look like kernel or DTS bugs rather than a stale-file problem.

---

## Pattern Analysis

This is an instance of a recurring class of failure: **invisible staging directory confusion**. Two prior incidents are related:

- `retrospective/bl33-address-mismatch.md` — the wrong binary was staged for flash because the build output path and the staging path were not explicitly linked.
- `retrospective/jlink-flash-failure.md` — flash succeeded but the binary was wrong due to a path assumption that was never verified.

The common pattern: a build tool writes output to path A; a flash tool reads from path B; there is no assertion connecting A to B; md5 verification at the flash stage catches content errors but not destination errors.

This class of failure recurs because the knowledge "which directory does the flash tool read from" is never captured durably. It exists in `.mcp.json` and MCP server code, but not in the working memory (MEMORY.md, rules, plan files) that an agent consults when staging files.

---

## Proposals

### Immediate Fix

**1. Update MEMORY.md with the definitive staging path.**
Record the resolved setools_dir as an absolute path so it loads every session.
- Effort: trivial
- Confidence: high — eliminates ambiguity in all future sessions

**2. Update `plans/uart-console-bringup.md` to reference the correct path.**
The plan currently lists `firmware/linux/alif-e7/setools/build/config/` for config files. Correct all references.
- Effort: trivial
- Confidence: high

### Code / Tooling Improvements

**3. Have the alif-flash MCP server log its resolved setools_dir at startup.**
Currently the server logs "Alif Ensemble Flash MCP server starting" with no path info. Adding one INFO line — `logger.info("setools_dir resolved: %s", os.path.abspath(setools_dir))` — in `__main__.py` after `create_server()` would make the log immediately diagnostic. This would have turned log line 1 into the evidence needed to catch the confusion.
- File: `claude-mcps/alif-flash/src/alif_flash/__main__.py`
- Effort: trivial
- Confidence: high — the log would have surfaced the issue in the first session

**4. Have the MCP's `gen_toc` tool return the absolute setools_dir in its response.**
The tool response currently returns success/failure and the ATOC path. Adding `setools_dir: <absolute path>` to the response gives the calling agent an explicit confirmation of where files are expected.
- File: `claude-mcps/alif-flash/src/alif_flash/isp.py`, `gen_toc()` return value
- Effort: small
- Confidence: high

**5. Treat the `AppTocPackage.bin not found` warning as an error.**
When flash is called and `AppTocPackage.bin` is absent, the MCP currently logs a WARNING and continues flashing the non-ATOC images. The correct behavior is to return an error: if AppTocPackage.bin is missing, gen_toc was never run against the right config in the right directory. Proceeding silently masks the mismatch.
- File: `claude-mcps/alif-flash/src/alif_flash/isp.py`, `flash_images()` around line 577
- Effort: trivial
- Confidence: high — this is what allowed two complete bad flash cycles (log lines 1087-1121)

### Process Improvements

**6. Add a setools-specific staging step to the pre-flash verification rule.**
The existing rule in `.claude/rules/pre-flash-verification.md` checks artifact content but not destination. Add a mandatory check: before copying any artifact, confirm the destination directory is `$(realpath tools/setools/build/images/)` by running `mcp__alif-flash__gen_toc` with a dry-run or by checking the log's resolved path.
- Effort: small
- Confidence: high

**7. Add a workspace README entry or sticky comment in both setools directories.**
Place a `README.txt` or `_THIS_DIR_IS_NOT_USED_BY_MCP.txt` in `firmware/linux/alif-e7/setools/build/images/` to make it visually clear that this directory is not the MCP's staging target. This is a low-tech guard against future confusion.
- Effort: trivial
- Confidence: medium (only helps if the directory is browsed, not if paths are typed from memory)

### Testing Improvements

**8. Add a test that verifies gen_toc uses an absolute, workspace-rooted setools_dir.**
The alif-flash test suite has 107 tests but none verify path resolution. Add a test that instantiates the server with `--setools-dir ./tools/setools` and a mocked cwd = workspace root, then asserts the resolved path is `<workspace>/tools/setools`.
- File: `claude-mcps/alif-flash/tests/test_isp.py` or a new `test_server_paths.py`
- Effort: small
- Confidence: medium (covers the specific path resolution, not the staging workflow end-to-end)

### Knowledge Capture

**9. Capture the setools path resolution fact as a knowledge item.**
Tag it `alif-e7`, `flash`, `gotcha`. Include: the resolved absolute path, why `cwd` in `.mcp.json` does not affect `--setools-dir` resolution, and that Claude Desktop always spawns MCP processes from the workspace root.
- Effort: trivial
- Confidence: high

---

## Recommended Action Plan

**Do Now (blocks further work):**

1. Update `MEMORY.md` with the definitive staging path:
   `tools/setools/build/images/` is the ONLY directory the alif-flash MCP reads for artifacts. All DTBs, kernels, TF-A binaries must be copied here.

2. Fix `plans/uart-console-bringup.md` to reference `tools/setools/build/config/` and `tools/setools/build/images/` throughout.

**Do Soon (prevents recurrence):**

3. Add startup log line to `alif-flash/__main__.py`: `logger.info("setools_dir: %s", os.path.abspath(setools_dir))`. This makes the path visible in `/tmp/alif-flash.log` from the first line of every server start. (trivial)

4. Change `AppTocPackage.bin not found` from WARNING to ERROR in `isp.py`. Return an error response rather than continuing the flash. (trivial)

5. Update `.claude/rules/pre-flash-verification.md` to add: "Before staging any artifact, verify the destination is in the MCP's actual setools_dir (`tools/setools/build/images/`), not `firmware/linux/alif-e7/setools/`." (small)

**Do Later (systemic improvement):**

6. Add `setools_dir` to the gen_toc tool response. Gives the calling agent an explicit confirmation. (small)

7. Add path resolution unit test to the alif-flash test suite. (small)

8. Place a marker file in `firmware/linux/alif-e7/setools/build/images/` indicating it is not the MCP staging directory. (trivial)

---

## Knowledge to Capture

The following should be recorded immediately and persist across sessions:

**For MEMORY.md:**
```
## alif-flash MCP: setools Staging Directory

The MCP's setools_dir resolves to:
  /Users/danahern/code/claude/work/tools/setools/

NOT firmware/linux/alif-e7/setools/ (that is the upstream release unpack location).

Claude Desktop spawns all MCP processes from the workspace root regardless of the
'cwd' field in .mcp.json. So --setools-dir ./tools/setools becomes:
  <workspace-root>/tools/setools/

Artifacts (DTBs, kernels, TF-A) must be copied to:
  tools/setools/build/images/

Config JSON files are at:
  tools/setools/build/config/
```

**For `.claude/rules/pre-flash-verification.md`:**
Add a new section "Staging Directory Verification" before "DTB Verification":
```
### Staging Directory Verification (check FIRST)
1. Confirm destination is tools/setools/build/images/ (NOT firmware/linux/alif-e7/setools/)
2. Verify md5 of artifact in tools/setools/build/images/ matches the build output
3. Run gen_toc after any artifact update — AppTocPackage.bin must be regenerated
4. Check /tmp/alif-flash.log first line for "setools_dir:" to confirm MCP's resolved path
```

**For knowledge system:**
Capture via `mcp__knowledge__capture` with tags `["alif-e7", "flash", "gotcha", "setools"]`:
- Title: "alif-flash MCP setools_dir resolves to workspace/tools/setools/ (not firmware/)"
- Body: Full path explanation including Claude Desktop cwd behavior and the two-directory confusion risk
