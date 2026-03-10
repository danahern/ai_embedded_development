# Retrospective: Agent Failed to Discover embedded-probe JLink Backend for Cortex-A32

**Date**: 2026-03-09
**Severity**: High — wasted engineering time, produced MCP-first policy violation, created wrong artifacts (custom probe-rs YAML)
**Related retrospectives**: `dtb-verification-skip.md`, `agent-process-failure.md`

---

## Incident Summary

The agent needed to read memory from a Cortex-A32 core on the Alif E8 board via JLink. The correct approach was to call `embedded-probe.connect()` with `target_chip = "AE822FA0E5597_A32_0"` (or the generic `"Cortex-A32"`), which would have triggered the `connect()` auto-fallback to the JLink backend when probe-rs rejected the A32 chip name. Instead, the agent (1) tried to create a custom probe-rs target YAML for the A32 core, (2) when that failed due to a JLink GUI dialog from a device name mismatch, fell back to raw Bash `JLinkExe` commands, and (3) only discovered the embedded-probe JLink backend after the user pointed it out. The entire detour — YAML creation, failed connect, Bash CLI usage — was avoidable. The JLink backend for this exact use case (`Cortex-A32` debug on Alif) was already registered in `list_targets` output with chip name `"Cortex-A32"` and notes documenting read-only use after SE boot.

---

## Timeline

| Event | What happened | What should have happened |
|-------|--------------|--------------------------|
| Agent needs A32 memory read | Assumes probe-rs can't handle A32 | Call `list_targets` to discover known chip names |
| Agent checks CLAUDE.md description | Sees "ARM Cortex-M, RISC-V, and Xtensa" in header | Should have read the JLink auto-fallback note in CLAUDE.md key details |
| Agent creates probe-rs target YAML | Manually authors a YAML for Cortex-A32 core | JLink backend handles A32 natively; no YAML needed |
| Connect fails with GUI dialog | Wrong device name triggers JLink device selector UI | Correct chip name from `list_targets` would not trigger this |
| Agent falls back to Bash `JLinkExe` | Direct CLI violation of MCP-first policy | Should have stopped, read `debugger_tools.rs` or CLAUDE.md more carefully |
| User points out JLink backend in `src/backend/jlink.rs` | Agent reads the file, sees the backend | Should have read this at session start |

---

## Root Cause Analysis

### Causal Chain

```
Symptom: Agent uses Bash JLinkExe to read A32 memory
  <- Proximate: Agent concluded embedded-probe cannot handle Cortex-A32
    <- Contributing: CLAUDE.md header says "ARM Cortex-M, RISC-V, and Xtensa"
      <- Contributing: JLink auto-fallback behavior is not documented in CLAUDE.md
        <- Contributing: Agent did not call list_targets before attempting connect
          <- Contributing: Agent did not read the backend source before concluding "not supported"
            <- Contributing: Forward-momentum + wrong assumption = no verification step
              <- Systemic: CLAUDE.md documents tools but does not document the JLink fallback capability
                <- Systemic: "Call list_targets before connect" rule exists but is not applied to non-Cortex-M targets
                  <- Systemic: No rule specifically states "embedded-probe handles Cortex-A via JLink fallback"
```

### The 5 Whys

**Why did the agent use Bash JLinkExe?**
The agent concluded embedded-probe was not capable of debugging the Cortex-A32, and that the JLink fallback was not present or not documented.

**Why did the agent conclude embedded-probe could not handle Cortex-A32?**
The CLAUDE.md header describes the MCP as supporting "ARM Cortex-M, RISC-V, and Xtensa targets." Cortex-A32 is not listed. The agent read this as a hard capability boundary rather than a description of the primary probe-rs target families.

**Why is Cortex-A32 not listed in the CLAUDE.md capability header?**
Because probe-rs does not natively support Cortex-A. The A32 support comes through the JLink auto-fallback backend (`src/backend/jlink.rs`), which is a secondary capability. The CLAUDE.md describes the primary probe-rs path, not the fallback path. The fallback's scope — "any chip in Segger's device DB" — is documented in the `mod.rs` comment but not surfaced in CLAUDE.md.

**Why didn't the agent try `list_targets` before assuming incapability?**
The `CRITICAL: Always call list_targets before connect` rule in CLAUDE.md says "do not guess or fabricate chip names." The agent's interpretation was: "I already know probe-rs doesn't support A32, so list_targets is irrelevant." The rule was understood as a chip-name correctness rule, not as a capability discovery mechanism that could reveal the JLink fallback path and its known chip names.

**Why wasn't there a rule specifically for Cortex-A / JLink fallback?**
This is the first time the Cortex-A32 debug path was exercised on this project. The JLink backend was built and documented in source code, but the knowledge was never surfaced to the CLAUDE.md or a rules file accessible to the agent at session start.

### Systemic Root Cause

Two independent systemic failures compounded each other:

1. **Documentation gap**: The embedded-probe CLAUDE.md documents the probe-rs capability boundary as the full capability of the MCP. The JLink auto-fallback — which extends the MCP to "any chip in Segger's device DB" — is only visible in the source code (`mod.rs` comment) and the `list_targets` output. An agent reading CLAUDE.md and seeing "Cortex-M, RISC-V, Xtensa" has no signal that A32 is reachable through a different backend.

2. **Wrong inference without verification**: The agent made a capability inference ("embedded-probe does not support A32") and acted on it without verifying: (a) reading `list_targets` output, (b) reading the backend source, or (c) attempting `connect()` to let the auto-fallback speak for itself. Under forward momentum, inference-as-fact is the default mode — verification requires active effort.

Both failures are consistent with recurring patterns documented in this repository's retrospectives. Neither is new.

---

## Contributing Factors

1. **Misleading capability summary in CLAUDE.md**: The first line of `embedded-probe/CLAUDE.md` reads "Supports ARM Cortex-M, RISC-V, and Xtensa targets through J-Link, ST-Link, CMSIS-DAP, and ESP-USB-JTAG probes." The phrase "J-Link" here refers to J-Link as a *probe type*, not as an independent *execution backend*. The distinction matters: J-Link as probe type connects through probe-rs; J-Link as backend connects through JLinkExe subprocess and can reach targets probe-rs cannot. This distinction is invisible to an agent reading the summary.

2. **Auto-fallback is invisible until you read source**: The fallback from probe-rs to JLinkExe is implemented silently in `connect()` (lines 222-288 of `debugger_tools.rs`). When probe-rs rejects a chip name, connect retries via JLinkExe automatically, using the same `target_chip` argument as the JLinkExe device name. This elegant design is completely undocumented in CLAUDE.md. A user (or agent) who has never seen a JLinkExe backend session response has no reason to expect this behavior.

3. **`list_targets` not consulted before capability conclusion**: The CLAUDE.md contains "CRITICAL: Always call `list_targets` before `connect`. Do NOT guess or fabricate chip names." The agent did not violate this literal rule — it never called `connect()` at all. But the spirit of the rule is capability discovery, not just name lookup. The `list_targets` output includes "Alif E7 A32" with `chip: "Cortex-A32"` and `probe_type: "JLink (JTAG, read-only after SE boot)"`. Calling `list_targets` first would have immediately revealed the supported path.

4. **Deferred tool loading friction**: embedded-probe is a deferred MCP tool. Calling it requires first issuing a ToolSearch to load it. Under pressure to solve a hardware problem, adding a two-step "load the tool, then use it" workflow is friction that can erode MCP-first behavior — especially when the agent believes the tool is incapable of the task anyway.

5. **Wrong diagnostic approach: build before verify**: Instead of calling `list_targets` or attempting `connect()` (which would either work or produce a useful error), the agent jumped to "build a custom target YAML" — creating something new to solve a problem that didn't exist. The 3-failures-before-stopping rule from `agent-process.md` should have triggered a capability audit before the YAML creation attempt.

6. **No Cortex-A debug rule auto-injects**: There is no `.claude/rules/` file that auto-injects when working with Cortex-A targets. The `alif-e7-hardware.md` and `alif-e8-hardware.md` files mention JLink device names but do not say "use embedded-probe with chip name X — it will JLink-fallback automatically." This knowledge existed only in source code.

---

## Pattern Analysis

This is the **third incident** in this project where the agent violated MCP-first policy by using Bash JLink/debug CLI commands:

| Incident | Root Pattern |
|----------|-------------|
| `dtb-verification-skip.md` | JLinkExe via Bash during DTB debugging (caught and documented) |
| `dtb-verification-skip.md` (same session) | Second MCP-first violation in same session |
| **This incident** | JLinkExe via Bash because agent assumed embedded-probe incapable |

The prior two incidents were caused by deferred-tool friction (known, documented, not yet fully resolved). This incident has a different root: the agent made a capability inference that was wrong and acted on it without verification. The mechanism is different but the outcome is the same: Bash CLI used instead of MCP.

There is also a structural parallel to the DTB pipeline opacity failure (`dtb-verification-skip.md`): in both cases, the agent's mental model of a system's capabilities was wrong in a way that led to skipping a tool that would have done the right thing. In the DTB case, the agent believed "correct DTS → correct DTB" (wrong because of DCT pipeline). In this case, the agent believed "embedded-probe only supports Cortex-M" (wrong because of JLink backend). Both are false capability-boundary beliefs that propagated into wrong behavior without a verification step.

This is recurring issue pattern #9 from MEMORY.md: "Deferred MCP tool friction causes MCP-first violations." But this incident adds a new variant: the friction is not just mechanical (deferred tool loading), but cognitive — the agent believed the tool couldn't do the task and therefore didn't even try to load it.

---

## Impact Assessment

**Severity**: High

- Direct: Engineering time wasted on YAML creation (a dead end), failed connect attempts, and Bash CLI usage
- Indirect: Created wrong artifact (the custom probe-rs YAML) that may confuse future sessions
- Policy: MCP-first policy violated; if the Bash usage succeeded and was not caught, it would not appear in MCP logs
- Opportunity cost: The correct approach (connect → JLink fallback) requires zero custom code

---

## Proposals

### 1. Fix the embedded-probe CLAUDE.md capability summary
**What**: Update the first line of `/Users/danahern/code/claude/work/claude-mcps/embedded-probe/CLAUDE.md` to make the JLink backend explicit:

Current:
```
Embedded debugging and flash programming MCP server via probe-rs. Supports ARM Cortex-M,
RISC-V, and Xtensa targets through J-Link, ST-Link, CMSIS-DAP, and ESP-USB-JTAG probes.
```

Proposed:
```
Embedded debugging and flash programming MCP server. Primary backend: probe-rs (ARM Cortex-M,
RISC-V, Xtensa). Secondary backend: JLinkExe subprocess (auto-fallback for any chip in Segger's
device DB, including Cortex-A32). If probe-rs rejects a chip, connect() retries via JLinkExe
automatically using the same chip name as the JLinkExe device name.
```

Also add a dedicated "JLink Auto-Fallback" section before the tools table explaining when it activates and what chips it covers (see Proposal 2 for content).

- **Effort**: trivial
- **Confidence**: high — directly addresses the documentation gap that caused the wrong capability inference
- **Risk**: none

### 2. Add JLink fallback section to embedded-probe CLAUDE.md
**What**: Add to CLAUDE.md before the tools table:

```markdown
## JLink Auto-Fallback Backend

When `connect()` is called with a J-Link probe and probe-rs fails to attach (e.g., unsupported
chip like Cortex-A32), the MCP automatically retries using JLinkExe as a subprocess backend.
The `target_chip` argument is passed directly to JLinkExe as the device name.

**Supported operations via JLink backend:**
- halt, run, reset, step, get_status
- read_memory, write_memory
- read_registers, write_register
- flash_erase, flash_program (loadbin/loadfile)

**Not available via JLink backend:** RTT, breakpoints, watchpoints, core_dump, stack_trace

**Chip names for Alif E7/E8 Cortex-A32:**
- Generic: `"Cortex-A32"` (JTAG, read-only after SE boot — recommended for memory reads)
- E7 specific: `"AE722F80F55D5_A32_0"`, `"AE722F80F55D5_A32_1"`
- E8 specific: `"AE822FA0E5597_A32_0"`, `"AE822FA0E5597_A32_1"`

**Important:** Always use JTAG interface for A32 (`interface: "JTAG"` is auto-set; SWD is
standard for M55 cores). A32 MRAM is write-protected after SE boot — use for reads only.
```

- **Effort**: small
- **Confidence**: high
- **Risk**: none

### 3. Add a Cortex-A debug rule to alif-common.md
**What**: Create or update `.claude/rules/alif-common.md` to include:

```markdown
## Cortex-A32 Debugging via embedded-probe

DO NOT use Bash JLinkExe for Cortex-A32 memory reads or debug operations.
Use the embedded-probe MCP. connect() auto-falls-back to JLinkExe for Cortex-A targets.

Procedure:
1. Load embedded-probe: ToolSearch "select:mcp__embedded-probe__connect"
2. Call list_targets — confirm "Alif E7 A32" or "Alif E8 A32" appears
3. Call connect(target_chip="Cortex-A32", probe_selector="auto", speed_khz=4000)
   - probe-rs will reject this chip name
   - connect() will auto-retry via JLinkExe with device="Cortex-A32"
   - Session ID returned uses JLink backend
4. Use read_memory, read_registers, halt, reset with the session ID

For E7: chip names "AE722F80F55D5_A32_0" or "AE722F80F55D5_A32_1" also work.
For E8: chip names "AE822FA0E5597_A32_0" or "AE822FA0E5597_A32_1" also work.

NEVER use Bash JLinkExe for A32 operations. The MCP handles this correctly.
```

- **Effort**: small
- **Confidence**: high — auto-injects when editing alif files
- **Risk**: none

### 4. Strengthen the pre-flash-verification.md JLink MCP section
**What**: The existing section says "load it using ToolSearch." Extend it to add:

```markdown
If you believe embedded-probe is incapable of the operation (e.g., Cortex-A target):
- You are WRONG. Call list_targets first. The JLink backend covers any chip in Segger's DB.
- The CLAUDE.md summary says "Cortex-M, RISC-V, Xtensa" — this describes probe-rs primary path.
  JLink fallback adds Cortex-A32 and other non-probe-rs targets automatically.
- Always attempt connect() before concluding incapability.
```

- **Effort**: trivial
- **Confidence**: medium — the same person who violated this before will also skip reading this extension

### 5. Capture knowledge item for embedded-probe JLink fallback
**What**: Capture a knowledge item tagged `embedded-probe`, `jlink`, `cortex-a32`, `alif`, `debug` covering the auto-fallback behavior, the A32 chip names, and the JTAG requirement. Filed as severity `critical` to appear in gotchas if regenerated.

- **Effort**: trivial
- **Confidence**: high — surfaces via `knowledge.search("A32 debug")` or `knowledge.search("embedded-probe JLink")`

### 6. Add a "capability boundary verification" step to agent-process.md
**What**: Add to `.claude/rules/agent-process.md` under the escalation section:

```markdown
## Before Concluding Any Tool Is Incapable

If you find yourself about to create a workaround because "Tool X can't do Y":
1. Read Tool X's CLAUDE.md fully (not just the header)
2. Call list_targets / list_probes / equivalent capability-discovery tool
3. Attempt the operation and read the error message carefully
4. Check MEMORY.md for related notes

Only after these steps may you conclude the tool lacks the capability. If the conclusion is correct,
that is a documentation gap — capture it. If the conclusion is wrong, you saved yourself a detour.

The cost of these checks: 2 minutes. The cost of skipping them: the detour you're trying to avoid.
```

- **Effort**: small
- **Confidence**: medium — advisory; depends on agent reading agent-process.md
- **Risk**: none

### 7. Delete the incorrect custom probe-rs target YAML (if created)
**What**: Remove any custom YAML file created during the failed attempt to add Cortex-A32 to probe-rs. These files are wrong artifacts — probe-rs does not support Cortex-A and a YAML will not fix that.
- **Effort**: trivial (if the file exists)
- **Confidence**: high
- **Risk**: none

---

## Recommended Action Plan

### Do Now (prevents recurrence in next session):

1. **Fix embedded-probe CLAUDE.md** (Proposals 1+2): Update the capability summary and add the JLink auto-fallback section. The documentation gap is the primary root cause. Every future session reads CLAUDE.md; fixing it has immediate effect.

2. **Capture knowledge item** (Proposal 5): Zero-cost, surfaces the right approach via search. Do immediately.

3. **Add Cortex-A rule to alif-common.md** (Proposal 3): Auto-injects when editing alif files, adds zero friction to the correct workflow while blocking the wrong one.

### Do Soon (systemic process improvement):

4. **Update pre-flash-verification.md** (Proposal 4): The JLink MCP section already exists; extend it with the "you are wrong about incapability" language.

5. **Add capability-verification step to agent-process.md** (Proposal 6): Generalizes the lesson from this incident to any tool-incapability conclusion.

### Do Later (cleanup):

6. **Remove wrong artifacts** (Proposal 7): If the custom probe-rs YAML exists in the workspace, delete it before it causes confusion.

---

## Knowledge to Capture

| Finding | Capture target | Tier |
|---------|---------------|------|
| embedded-probe connect() auto-falls-back to JLinkExe for Cortex-A32 | knowledge.capture() | Tier 3 |
| Cortex-A32 chip names for E7/E8: `AE722F80F55D5_A32_0`, `AE822FA0E5597_A32_0` | alif-common.md rule | Tier 2 |
| JLink backend operations: halt/run/reset/read_memory/write_memory/read_registers | CLAUDE.md section | Tier 2 |
| CLAUDE.md "Cortex-M, RISC-V, Xtensa" does NOT define the full capability boundary | pre-flash-verification.md | Tier 2 |
| Wrong inference without verification is a recurring cause of MCP-first violations | MEMORY.md pattern #10 | Tier 1 |
| Always call list_targets not just for chip names but for capability discovery | agent-process.md | Tier 2 |

---

## Blameless Assessment

Two independent systemic gaps enabled this failure.

**Gap 1: Documentation describes the primary path only.** CLAUDE.md accurately describes probe-rs capabilities. It does not describe the JLink fallback, which is a secondary execution path that extends those capabilities significantly. An agent reading only CLAUDE.md will conclude Cortex-A32 is unsupported. This is a false conclusion, but the documentation supports it. The fix is straightforward: add the fallback description to CLAUDE.md.

**Gap 2: Capability inference without verification is structurally identical to prior failures.** Every MCP-first violation in this project has followed the same logic: "Tool X cannot do Y, therefore I must use Bash." This incident adds the cognitive variant: "I already know the tool can't do this, so checking is unnecessary." The fix for the mechanical variant (deferred tool friction) is in progress. The cognitive variant needs its own countermeasure: a required verification step before any capability conclusion triggers a workaround. That step is documented in Proposal 6.

Neither gap requires exceptional agent behavior to close. Both are addressable with documentation updates and a one-line rule addition. The cost of not closing them is another incident of the same class.
