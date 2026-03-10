---
paths: ["**/*.md", "**/plans/**", "**/retrospective/**", "**/alif-e7/**", "**/yocto/**", "**/meta-eai/**", "claude-mcps/**"]
---

# Agent Process Rules

Derived from the 2026-03-01 persistent overlayfs incident retrospective.
Full analysis: `retrospective/agent-process-failure.md`.

## Escalation Threshold: 3 Consecutive Failures = STOP

After 3 consecutive unexpected failures in a single session, do NOT attempt a 4th fix.
Run the structured investigation before continuing:

```
1. What was I trying to accomplish? (restate the original goal)
2. What approach was I taking? (enumerate the steps)
3. What assumption does each failed step rely on?
4. Which assumptions have been verified by experiment vs. inferred?
5. Which assumption, if wrong, would explain all failures?
6. What is the minimal test to verify or falsify that assumption?
```

**Why**: Six consecutive failures in the overlayfs session all could have been avoided if anyone had
stopped at failure 3 to ask "what haven't we verified?" instead of finding the next fix to apply.

## User Process Signals Are Not Debatable

When the user says "let's step back and understand X" or "maybe we should investigate Y first":
- **Do it. Do not evaluate whether you agree.** Do not say "we're close though."
- The user's meta-level assessment of session health is authoritative.
- The only correct response is: "Good call. Let me audit [X] before we proceed."

**Why**: During the incident, the user suggested investigating the flash process. The agent assessed
"we're close" and pushed forward. The user was right. The agent wasted 2+ additional hours.

## Pre-Flight Checklist Before Expensive Operations (>10 min)

Any operation taking more than 10 minutes requires a pre-flight check before starting.
"I've done this before" is not a pre-flight check.

### Step 1: Log Parameters (BEFORE starting)

Append an entry to `builds/BUILD_LOG.md` capturing the **full recipe** — everything needed to reproduce this build/flash. The goal is that anyone reading the log can understand exactly what was built, with what, and why.

```markdown
## <ISO date> — <short description>

### Parameters
- **Operation**: <kernel build | OSPI flash | MRAM flash | Yocto build | BFT | ...>
- **Target**: <board/chip>
- **Tool**: <MCP tool being used>

### Recipe
<Include ALL inputs that define what gets built or flashed. Pick the relevant sections:>

**Kernel** (if kernel build or flash):
- Config fragments: <list .cfg files and key CONFIG_ values>
- Defconfig: <base defconfig>
- Key overrides: <CONFIG_X=y/n that differ from defconfig>

**TF-A** (if TF-A build or flash):
- Build flags: <ENABLE_PIE=1, FLASH_EN=1, HYPRAM_EN=1, etc.>
- Source modifications: <any uncommitted changes, e.g. USB clock enables in sp_min_main.c>

**Yocto image** (if Yocto build):
- Image recipe: <e.g. alif-tiny-image>
- IMAGE_INSTALL additions: <packages added>
- Layer modifications: <changed .bb/.bbappend files>

**DTB** (if DTB build or flash):
- Base DTB: <source .dts file>
- fdtput modifications: <list of changes applied>

**Flash layout** (if flashing):
- ATOC config: <config file name>
- Images and addresses: <image → address mapping>
- Flash method: <SE-UART ATOC | J-Link MRAM | TF-A OSPI programmer>

**Artifacts**:
- <file path> (<size>) → <destination>
```

This creates the record BEFORE the operation runs, so if it fails or hangs we know exactly what was attempted.

### Step 2: Run Preflight Checks

**Kernel build pre-flight**:
- Is the kernel config fragment inside the container (not just on the host)?
- What is the current kernel binary timestamp? (baseline for post-build verification)
- Am I using `kernel_rebuild` (correct) or raw `cleansstate + compile -f` (wrong)?

**OSPI/MRAM flash pre-flight**:
- Have artifacts been staged via `stage-ospi.sh`? Do filenames match what the flash config expects?
- Is this a persistent update? If yes: are you using SE-UART ATOC (`gen_toc + flash`), NOT `jlink_flash`?
- If using a flash config for the first time: has it been verified to survive a power cycle?

**New flash path pre-flight** (any new `*-jlink.json` or `*-atoc.json` config):
- Flash a minimal known-good payload, power cycle, confirm it persisted. Only then flash real images.

### Step 3: Log Preflight Results and Outcome (AFTER completing)

Update the same entry in `builds/BUILD_LOG.md`:
```markdown
### Preflight
- [x] Config fragment inside container
- [x] Using kernel_rebuild
- [n/a] Flash path persistence verified

### Result
- **Status**: PASS | FAIL
- **Duration**: ~Xm
- **Output**: <ROM/RAM sizes, error messages, key observations>
- **Notes**: <anything unexpected>
```

## Knowledge Generalization: Always Ask the General Principle

Before using any tool in a new context, check MEMORY.md and the knowledge corpus for warnings
about that tool. If a warning exists for an adjacent use case, ask:

> "What general principle does this warning embody? Does it apply to what I'm about to do?"

**Example that was missed**: MEMORY.md said "NEVER use jlink_flash to update bl32 — bypasses ATOC."
The agent then used jlink_flash for kernel and rootfs on the same hardware. The general principle
("don't use jlink_flash for ATOC-managed images") was never extrapolated from the specific case (bl32).

## Launch Specialized Agents Earlier, Not Later

The `build-toolchain-expert` and `kernel-reviewer` agents exist for a reason. Lower the threshold:

- **After the first kernel build failure** that is not an obvious syntax error: launch `build-toolchain-expert`
  to audit the complete build pipeline before attempting another build.
- **After any flash failure on recently reconfigured hardware**: launch `build-toolchain-expert`
  to verify the flash chain end-to-end before spending another flash cycle.
- **Any time the user expresses uncertainty about the flash process**: launch proactively, before the next attempt.

The cost of launching a specialized agent: 2-5 minutes.
The cost of not launching one when you should have: hours. (See the 2026-03-01 incident.)

## Before Concluding Any Tool Is Incapable

If you find yourself about to create a workaround because "Tool X can't do Y":

1. Read Tool X's CLAUDE.md **fully** (not just the header summary)
2. Call the tool's capability-discovery function (`list_targets`, `list_probes`, `list_apps`, etc.)
3. Attempt the operation and read the error message carefully — errors are documentation
4. Check MEMORY.md and knowledge for notes about the tool + target combination

Only after these four steps may you conclude the tool lacks the capability. If you confirm it truly
cannot, that is a documentation gap — capture it with `knowledge.capture()`. If the conclusion was
wrong, you saved yourself the detour.

**Known example**: embedded-probe CLAUDE.md says "Cortex-M, RISC-V, Xtensa" but the JLink fallback
backend handles Cortex-A32 automatically via `connect()` auto-retry. The header was misleading; the
full capability required reading the JLink Auto-Fallback section. See
`retrospective/embedded-probe-jlink-backend-missed.md`.

Cost of the four checks: 2 minutes. Cost of skipping them: the detour you were trying to avoid.

## "We're Close" Is Not a Probability Estimate — It Is Optimism Bias

The phrase "we're close" or "this should be the last issue" is a known cognitive failure mode.
It is generated by goal-anchoring, not by evidence.

Evidence that the goal is achievable by the current approach looks like:
- The approach has been used successfully on this hardware before
- The current obstacles are well-understood and the fixes are verified in MEMORY.md
- No untested assumptions remain in the critical path

If ANY of those are false, "we're close" is wishful thinking, not analysis.

## Knowledge from Inference vs. Knowledge from Observation

When capturing knowledge, be explicit about its epistemic basis:
- **Observed**: "We ran X, power cycled, and confirmed Y persisted." Directly confirmed.
- **Inferred**: "We believe X because of principle Y." Reasonable, not yet confirmed.

Inferred knowledge about high-stakes operations (flash persistence, power cycle survival, boot sequence)
must be treated as unverified hypothesis — not actionable truth — until confirmed by experiment.

The k-b4a4b26f incident: "jlink_flash is safe for OSPI writes because OSPI doesn't go through
ATOC validation" was captured as inferred knowledge and treated as observed truth. It was wrong,
and it drove 6 hours of wasted work.
