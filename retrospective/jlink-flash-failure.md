# Retrospective: J-Link Flash Failure — SE Overwrites All ATOC Images on Boot

**Date**: 2026-03-01 (session), retrospective written 2026-03-02
**Duration**: ~6 hours of active work; zero net feature progress
**Severity**: High — multiple hours lost, systemic knowledge gap exposed
**Status**: Root cause confirmed, mitigations in progress

---

## Executive Summary

A full day (~6+ hours) was spent building, staging, and flashing a new Yocto kernel and rootfs to an Alif E7 board via J-Link. Every flash operation reported success and verification passed. Changes never took effect after a power cycle. The root cause is that the Secure Enclave (SE) reprograms ALL ATOC-managed images from its internal storage on every boot, silently overwriting any J-Link writes to OSPI or MRAM.

This failure was compounded by five independent build and staging failures before the definitive root cause was confirmed. The session wasted 6+ flash cycles (each 30+ minutes at ~6 KB/s), multiple kernel builds, and multiple debug sessions chasing the wrong problem.

The correct flash path — SE-UART via ATOC (`gen_toc` + `flash`) — was already partially documented for bl32, but the warning was scoped too narrowly. No one verified that J-Link writes to OSPI survived a power cycle before the `linux-boot-e7-ospi-jlink.json` config and the jlink-first operational rule were committed.

---

## Timeline

### Phase 1: Build Failures (before any flash attempt)

**~T+0:00 — Build attempt 1: Docker volume isolation (~60 min wasted)**

The Yocto build was triggered with a new `.cfg` kernel fragment. The fragment existed on the host at `firmware/linux/yocto/meta-eai/recipes-kernel/linux/files/jffs2.cfg` but the `yocto-build` container did not have the `meta-eai/` directory bind-mounted at the time. The build succeeded but the fragment was not seen by Yocto. The kernel was built without `CONFIG_JFFS2_FS`.

This same class of failure (Docker volume isolation) had occurred previously on 2026-02-26 (k-d373eec0 context for alif-apss-build). The knowledge was captured but never promoted to a rule or CLAUDE.md gotcha.

**~T+1:00 — Build attempt 2: Misdiagnosed as kernel-meta cache (~30 min wasted)**

The missing config was initially diagnosed as a kernel-meta cache problem rather than a Docker volume issue. Time was spent investigating `.kernel-meta` cache clearing before the real cause was identified.

**~T+1:30 — Fix: meta-eai bind mount added, container recreated**

The `yocto-build` container was recreated with the meta-eai directory bind-mounted. This fix was correct and was captured as a rule in `yocto-docker.md` (commit a41dd72).

**~T+2:00 — Build attempt 3: stale kernel (cleansstate doesn't clean work-shared) (~35 min wasted)**

After the bind mount fix, `bitbake linux-alif -c cleansstate && bitbake linux-alif` was used. `cleansstate` removes sstate caches but does NOT delete `work-shared/devkit-e8/kernel-source/`. The subsequent compile step ran Make against existing `.o` files with timestamps newer than the new `.config`. Make exited without recompiling. The binary appeared correct but lacked the new config options.

This failure class was already documented in MEMORY.md from a prior session (2026-03-01) as: "cleansstate + compile -f Does NOT Force Rebuild." The correct fix (`configure -f && compile -f`) was known but not applied.

**~T+2:35 — Build attempt 4: forced compile with wrong sequence (~15 min wasted)**

`do_compile -f` was forced without first running `do_configure -f`. Make's kbuild incremental behavior meant the binary was again not rebuilt. The `kernel_rebuild` MCP tool (added in commit a41dd72) that runs the correct sequence did not yet exist or was not used.

**~T+2:50 — Fix: kernel_rebuild tool used, correct binary produced**

The correct `configure -f → compile -f → deploy -f` sequence produced a rebuilt kernel with `CONFIG_JFFS2_FS=y`. The binary timestamp confirmed the new build.

### Phase 2: Flash Staging Failures

**~T+3:30 — Build attempt 5: wrong filenames in flash config (~36 min wasted)**

The first flash attempt used stale files. The flash config `linux-boot-e7-ospi-jlink.json` references `xipImage-ospi` and `rootfs-ospi.bin`, but Yocto outputs `xipImage` and `*.cramfs-xip`. The `stage-ospi.sh` script did not yet exist. The flash tool silently used previously staged files from an earlier build. The resulting flash operation wrote the old kernel without JFFS2.

This staging mismatch was identified and the `stage-ospi.sh` script was created (commit f72b7ed, 2026-03-01 17:37).

**~T+4:00 — Build attempt 6: correct build, correct filenames, flash succeeds (~36 min wasted)**

After staging, `jlink_flash` with the OSPI FLM flash loader wrote the correct kernel (~3.75 MB) and rootfs to OSPI. Flash took approximately 36 minutes at ~6 KB/s. Verification passed.

### Phase 3: The Root Cause

**~T+4:36 — Power cycle: board boots with old kernel**

After the successful flash and verification, the board was power-cycled. The kernel that booted did not have `CONFIG_JFFS2_FS`. Kernel size matched the pre-JFFS2 binary.

**~T+4:45 — Debug: phram not available either**

A second test was performed: a DTB with `phram=mram_overlay,0x80380000,0x200000` was flashed to MRAM at 0x80010000 via `jlink_flash`. Verification passed. After power cycle: the old bootargs (no phram) were in effect.

**~T+5:00 — Additional test: rootfs init script**

A rootfs with a modified init script was flashed to OSPI at 0xC0000000 via `jlink_flash`. Verification passed. After power cycle: old init script was running.

**~T+5:15 — Root cause identified**

The pattern across three consecutive data points made the mechanism clear: the SE reprograms ALL ATOC-managed images from its internal storage on every boot. J-Link writes appear to succeed because they write to the correct physical addresses and the verify step reads back correctly. However, the SE reads its own copy of the images (stored during the last `alif-flash.flash()` call) and overwrites the OSPI and MRAM locations before the A32 core starts.

Knowledge item k-3b471ccd was captured.

**~T+5:30 — Session ended without feature progress**

The actual goal (verify MRAM MTD exists for Experiment 1 of the persistent overlayfs plan) was never attempted. Zero net progress on the feature.

---

## Root Cause Analysis

### Causal Chain

```
Symptom: 6 hours of work with zero feature progress
  |
  v
Proximate: J-Link OSPI/MRAM writes verified but overwritten by SE on boot
  |
  v
Contributing (build): 4 failed kernel builds before correct binary was produced
  |  Docker volume isolation (known prior failure class — not promoted to rule)
  |  cleansstate not cleaning work-shared (known prior failure class — not applied)
  |  Wrong command sequence (kernel_rebuild tool newly created, not yet used)
  |
  v
Contributing (staging): xipImage vs xipImage-ospi filename mismatch
  |  stage-ospi.sh did not exist yet
  |  alif-e7-hardware.md listed jlink_flash as the correct tool
  |
  v
Contributing (knowledge): Incorrect and contradictory rules in effect
  |  operational.md: "Always use J-Link (jlink_flash) for Alif E7 flashing"
  |  alif-common.md: "Use for ALL image updates (TF-A, DTB, kernel, rootfs)"
  |  MEMORY.md warning only scoped to bl32, not OSPI images
  |
  v
Systemic root cause: J-Link OSPI flash path was never verified end-to-end
  |  linux-boot-e7-ospi-jlink.json was created (commit 044c669, 2026-02-24)
  |  without testing that the flashed images survived a power cycle
  |  The J-Link MRAM write experience (~44 KB/s, write succeeds) was incorrectly
  |  generalized to OSPI without understanding the SE's image management model
```

### The Core Mechanism

The Alif E7 SE operates as a trust anchor for all boot images. When `alif-flash.flash()` is called with an ATOC config, the SE stores the images in its own protected internal storage and programs the MRAM/OSPI addresses. On every subsequent boot, the SE re-reads its internal storage and reprograms those same addresses. This is by design — it ensures boot image integrity.

J-Link can write to OSPI (via the FLM flash algorithm) and MRAM (via loadbin) because those are memory-mapped peripherals. The writes succeed at the hardware level. But the SE does not know about them, and overwrites them from its own copy before the A32 core starts.

This is NOT a bug. It is the expected security model. But it was never documented clearly for the OSPI images.

### Conflicting Prior Knowledge

The knowledge corpus contained directly contradictory information:

| Source | Statement | Correct? |
|--------|-----------|----------|
| `retrospective/alif-e7-first-boot.md` (Session 4, 2026-02-20) | "MRAM is write-protected from JLink — must use ISP for all MRAM writes" | Partially correct (MRAM is writable via JLink loadbin, but SE overwrites it) |
| `alif-common.md` (rules, current) | "Use jlink_flash for ALL image updates (TF-A, DTB, kernel, rootfs)" | WRONG |
| `operational.md` (rules, current) | "Always use J-Link (jlink_flash) for Alif E7 flashing, SE-UART as fallback only" | WRONG |
| `MEMORY.md` | "NEVER use jlink_flash to update bl32 — bypasses ATOC. Use SE-UART" | Correct but scope too narrow — only mentions bl32 |
| k-b4a4b26f (2026-02-26) | "jlink_flash is safe for OSPI writes (kernel, rootfs) which don't go through ATOC validation" | WRONG — this was the false belief that created the jlink OSPI path |

The knowledge item k-b4a4b26f (created 2026-02-26) contains the critical error: "jlink_flash is safe for OSPI writes (kernel, rootfs) which don't go through ATOC validation." This statement is incorrect — OSPI images ARE managed by ATOC. This knowledge item was captured after the MRAM-write-fails experience (which concerned ATOC checksum validation bricking the board, not SE image management), and the author incorrectly concluded that OSPI was exempt.

This incorrect belief became the `alif-common.md` rule ("Use jlink_flash for ALL image updates") and the `operational.md` rule ("Always use J-Link, SE-UART as fallback only"), which in turn drove the creation of `linux-boot-e7-ospi-jlink.json` (commit 044c669, 2026-02-24).

---

## Contributing Factors

1. **Knowledge generalization error**: The J-Link MRAM write speed (~44 KB/s) was correctly captured, then incorrectly generalized to OSPI without verifying the end-to-end behavior across a power cycle.

2. **No power-cycle verification requirement**: There was no established protocol requiring that a new flash path be verified to survive a power cycle before being committed as a rule or config file.

3. **Docker volume isolation (recurring)**: The same Docker volume isolation failure had occurred 3 days earlier. It was captured but never promoted to a rule. Two sessions (60 min + 30 min) were consumed by the same failure class.

4. **Known build procedure not applied**: The `cleansstate` + `work-shared` cache problem was documented in MEMORY.md. The correct procedure (`configure -f` before `compile -f`) was known but not followed. The `kernel_rebuild` MCP tool that enforces the correct sequence was only added mid-session.

5. **Staging script missing**: The filename mismatch between Yocto output names and flash config names had no automated fix at session start. The `stage-ospi.sh` script was created during the session, but only after a 36-minute flash cycle was wasted on stale files.

6. **Silent failure mode of J-Link OSPI flash**: The `jlink_flash` tool reports success and verification passes. There is no indication that the write will be overwritten. The failure is only visible after a power cycle.

7. **Flash cycle time amplifies every mistake**: At 6 KB/s for OSPI, each complete flash cycle takes 30+ minutes. A mistake that requires one additional flash cycle costs 30 minutes. Five such mistakes cost 2.5 hours on flash time alone.

---

## Pattern Analysis

### Recurring failure class: Docker volume isolation

This is the third occurrence:
- 2026-02-26: alif-apss-build Docker volume (knowledge item captured, not promoted)
- 2026-03-01 attempt 1: yocto-build Docker volume (knowledge item captured, rule added)
- This session: yocto-build Docker volume (same fix, resolved in ~30 min)

The rule in `yocto-docker.md` was added after the second occurrence. This session benefited from it marginally faster, but the initial mis-diagnosis as kernel-meta cache cost 30 minutes. The pattern is improving but not eliminated.

### Recurring failure class: Kernel rebuild with stale artifacts

This is the second occurrence:
- MEMORY.md records the first occurrence on 2026-03-01 with a full explanation
- This session: same failure, same incorrect command sequence

The `kernel_rebuild` MCP tool was added to prevent recurrence. This session used it correctly (eventually) and resolved correctly. The tool is the right fix; the residual issue is that the wrong commands were tried first before the correct tool was used.

### New failure class: Unverified flash paths committed as truth

This is the first documented occurrence of "flash config created without power-cycle verification." It is likely a systemic gap: any time a new flash config is created, it should be tested end-to-end. This did not happen for `linux-boot-e7-ospi-jlink.json`.

---

## Impact Assessment

**Direct impact**: ~6 hours of developer + agent time. Zero progress on the persistent overlayfs feature. 6+ flash cycles discarded, each consuming 30+ minutes.

**Near-misses**: If the J-Link flash path had been used for several more sessions before discovery, significantly more time would have been lost. The discovery came from triangulation across three independent tests in one session, not from a documented verification protocol.

**Blast radius**: Any session using `jlink_flash` to update kernel, rootfs, or DTB on the Alif E7 will silently fail. The `alif-e7-hardware.md` rule and `alif-common.md` rule actively steered toward this broken path. Any developer following these rules would waste at least one full flash cycle (30 min) before suspecting the flash tool.

**Severity rating**: High — hours of developer time lost, wrong rules actively injected into every session touching Alif E7 files.

---

## Proposals

### 1. Immediate Fixes

**1a. Fix the incorrect rules NOW (trivial effort, critical)**

`operational.md` and `alif-common.md` contain rules that actively direct toward the broken J-Link OSPI path. These must be corrected immediately.

`operational.md` — change the jlink-first rule to SE-UART-first for all boot images.
`alif-common.md` — remove "Use for ALL image updates" and replace with the SE-UART primary path.
`alif-e7-hardware.md` — update the flash layout table to note that images are programmed via SE-UART, not jlink_flash.

**1b. Fix MEMORY.md bl32 warning to cover all ATOC images (trivial effort, critical)**

Current: "NEVER use jlink_flash to update bl32 — bypasses ATOC. Use SE-UART (gen_toc + flash)"
Required: Generalize to ALL ATOC-managed images.

**1c. Deprecate linux-boot-e7-ospi-jlink.json (small effort, high confidence)**

The file `firmware/linux/alif-e7/setools/linux-boot-e7-ospi-jlink.json` exists as infrastructure for a flash path that does not work for persistent changes. It should either be deleted or have a prominent comment added explaining that J-Link OSPI writes are overwritten by the SE on every boot. Leaving it as-is creates a trap for any future developer.

### 2. Code and Configuration Changes

**2a. Add a warning comment to linux-boot-e7-ospi-jlink.json (trivial)**

Add a `"_WARNING"` key explaining that J-Link OSPI writes are overwritten by SE on every boot and this config is only useful for temporary debugging (memory reads, not persistent programming).

Effort: trivial. Confidence: high (passive protection, always visible).

**2b. Validate knowledge item k-b4a4b26f (trivial)**

The body of k-b4a4b26f still states "jlink_flash is safe for OSPI writes (kernel, rootfs) which don't go through ATOC validation." This is incorrect. The item should be updated with the corrected understanding and then the status set to deprecated (superseded by k-3b471ccd).

Effort: trivial. Confidence: high.

### 3. Process Improvements

**3a. Power-cycle verification protocol for new flash paths (small, high confidence)**

Before any new flash config file (`*-jlink.json`, `*-atoc.json`, etc.) is committed to the repository:
1. Flash a known test payload (e.g., kernel with unique version string)
2. Verify the payload reads back correctly
3. Power cycle
4. Verify the payload is still present post-power-cycle
5. Only commit after step 4 passes

This protocol would have caught the J-Link OSPI failure before `linux-boot-e7-ospi-jlink.json` was committed.

**3b. Post-flash power-cycle checklist (trivial, medium confidence)**

Add to the Alif E7 flash workflow: "After any flash operation, power cycle the board and verify that the changed behavior/content is observed. A successful verify-on-tool does NOT confirm persistent write."

### 4. Tooling Improvements

**4a. Add SE-UART OSPI flash path to alif-flash MCP (medium effort, high confidence)**

The current SE-UART (`alif-flash.flash`) only writes MRAM images. OSPI images require the TF-A MRAM staging programmer (see knowledge item k-f44cd4f4). The alif-flash MCP should expose an `ospi_flash()` tool that:
1. Splits the image into MRAM-sized chunks if needed
2. Writes each chunk to the MRAM staging area via SE-UART
3. Writes the OSPI programmer header to trigger TF-A to program OSPI
4. Power cycles and monitors for TF-A OSPI programming messages

This would make the correct path as easy to invoke as the (incorrect) `jlink_flash` path was.

Effort: medium (requires integrating the split/stage/cycle workflow). Confidence: high once implemented.

**4b. Add deprecation warning to jlink_flash when targeting ATOC addresses (medium effort, high confidence)**

The `jlink_flash` MCP tool could check if any of the target addresses (from the flash config) fall in the ATOC-managed regions (MRAM 0x80000000+, OSPI 0xC0000000+). If so, emit a prominent warning: "WARNING: This address is managed by the SE ATOC. J-Link writes will be overwritten on next power cycle. Use SE-UART flash() for persistent writes."

Effort: small (address range check in server.py or jlink.py). Confidence: high.

### 5. Knowledge Capture

**5a. Validate and promote k-3b471ccd (trivial)**

The knowledge item k-3b471ccd ("Alif E7: J-Link writes to OSPI and MRAM are overwritten by SE on every boot") is currently `unvalidated`. It should be set to `validated` so it can be promoted to rules and gotchas.

**5b. Regenerate rules and gotchas after validation (trivial)**

Once k-3b471ccd is validated, run `knowledge.regenerate_rules()` and `knowledge.regenerate_gotchas()` to promote this to Tier 1 and Tier 2 protection.

**5c. Capture the two-step OSPI flash path explicitly (small)**

The SE-UART OSPI flash path (MRAM staging + OSPI programmer header + power cycle sequence) should be captured as a concrete operational knowledge item with step-by-step commands, expected timing, and verification steps.

---

## Recommended Action Plan

### Do Now (blocks future work on this board)

1. **Fix `operational.md`**: Remove the "Always use J-Link, SE-UART as fallback" rule. Replace with the correct guidance: SE-UART via ATOC is required for all persistent image updates.

2. **Fix `alif-common.md`**: Remove "Use jlink_flash for ALL image updates." Replace with the two-tier model: SE-UART for persistent updates, J-Link only for temporary debugging.

3. **Fix `alif-e7-hardware.md`**: Flash layout table currently says "OSPI images flashed via `alif-flash.jlink_flash()`." Change to: "OSPI images programmed via SE-UART ATOC (`alif-flash.gen_toc` + `alif-flash.flash`)."

4. **Fix MEMORY.md**: Extend the bl32 J-Link warning to cover all ATOC-managed images (kernel, rootfs, DTB, bl32).

5. **Deprecate k-b4a4b26f**: The body states "jlink_flash is safe for OSPI writes." Update to mark as superseded by k-3b471ccd, correct the body.

6. **Update `plans/persistent-overlayfs.md`**: Add a note in the Implementation Plan and Verification sections that SE-UART is required for flashing (not J-Link).

### Do Soon (prevents recurrence)

7. **Add warning to linux-boot-e7-ospi-jlink.json**: Add a `"_WARNING"` key at the top of the JSON with an explanation that writes via this config are overwritten by SE on boot.

8. **Validate k-3b471ccd and regenerate rules/gotchas**: Promote the verified finding to Tier 1 and Tier 2 protection.

9. **Capture SE-UART OSPI flash workflow**: Document the complete step-by-step path including the MRAM staging mechanism, timing expectations, and verification steps.

### Do Later (systemic improvement)

10. **Add jlink_flash ATOC address warning in MCP**: Detect when target addresses are ATOC-managed and warn before proceeding.

11. **Implement `alif-flash.ospi_flash()` MCP tool**: Make the correct SE-UART OSPI path as ergonomic as jlink_flash was.

12. **Establish power-cycle verification protocol**: Add a checklist item to the plan lifecycle rules: any plan involving a new flash config must include a power-cycle verification step.

---

## Knowledge to Capture

| Item | Action |
|------|--------|
| SE overwrites all ATOC-managed OSPI and MRAM images on every boot | k-3b471ccd exists — validate it and regenerate rules/gotchas |
| k-b4a4b26f is incorrect ("jlink_flash safe for OSPI") | Deprecate, update body, mark superseded |
| SE-UART OSPI flash workflow (gen_toc + MRAM staging + header + power cycle) | New knowledge item needed |
| Power-cycle verification is required after any new flash path | Add to plan lifecycle rules |

---

## Appendix: Flash Speed Comparison

| Method | Speed | 10 MB flash time | Use case |
|--------|-------|-----------------|---------|
| SE-UART ISP (flash()) | ~5 KB/s | ~34 min | MRAM images via ATOC (persistent) |
| SE-UART + TF-A OSPI programmer | ~42 KB/s | ~4 min | OSPI images via ATOC (persistent) |
| J-Link FLM (jlink_flash) OSPI | ~6 KB/s | ~28 min | NOT persistent — SE overwrites on boot |
| J-Link loadbin MRAM | ~44 KB/s | ~4 min | NOT persistent — SE overwrites on boot |

The SE-UART + TF-A OSPI programmer path is not only the correct path — it is approximately 7x faster than J-Link FLM for OSPI. Using the wrong tool was simultaneously slower AND produced no result.
