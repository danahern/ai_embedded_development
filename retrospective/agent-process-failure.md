# Retrospective: Agent Process Failure — Persistent OverlayFS Day

**Date**: 2026-03-01 (incident), retrospective written 2026-03-02
**Duration**: ~6 hours of active work; zero net feature progress
**Severity**: High — process failure compounded every technical failure
**Related technical retrospective**: `retrospective/jlink-flash-failure.md`

---

## Executive Summary

On 2026-03-01, an attempt to add JFFS2 + phram to the Alif E7 kernel and verify experiment 1 of the persistent overlayfs plan resulted in zero feature progress after 6+ hours. Six complete build-flash cycles were executed — each taking 30 to 60 minutes — all of them ultimately irrelevant, because the definitive root cause (the SE overwrites all J-Link writes on every boot) was not discovered until hour 5, and would have been discovered in hour 1 if anyone had stopped to investigate the flash toolchain before launching the first build.

This retrospective is not about the technical failures. Those are documented in `retrospective/jlink-flash-failure.md`. This retrospective is about the agent behavior that allowed six expensive, stacked failures to accumulate without triggering a fundamental change in approach. The agent (Claude) operated in goal-pursuit mode throughout, repeatedly treating each failure as "one more fix away," ignoring the user's suggestion to stop and investigate the flash process, and failing to apply existing knowledge that was already in MEMORY.md. This document names those failures honestly and proposes concrete process changes to prevent recurrence.

---

## Timeline of Decisions (Not Events)

The technical timeline is in `jlink-flash-failure.md`. This section reconstructs the decision logic at each inflection point.

**T+0: Session starts. Goal is clear. Agent starts immediately.**

The goal is a simple kernel config change (add JFFS2), an init script update, build, flash, test. The agent assessed the task as straightforward and started executing without reviewing the flash tool chain or checking that the existing J-Link OSPI flash path had ever been verified end-to-end across a power cycle.

Decision made: Start building immediately. No pre-flight review of flash toolchain.
Correct decision: Run a pre-flight check — does the existing flash path work on a known-good image before modifying anything?

**T+1:00: Build 1 produces wrong binary. Diagnosis: kernel-meta cache.**

The first kernel build appeared to succeed but lacked the new config option. The initial diagnosis was a kernel-meta cache problem, not a Docker volume problem. Thirty minutes were spent investigating the wrong cause before the Docker volume isolation was identified.

Decision made: Push forward with incremental diagnosis, try the next plausible fix.
Correct decision: Before the second diagnosis attempt, check the knowledge base. The Docker volume isolation failure class was already documented (k-d373eec0 from 2026-02-26, three days earlier). A 30-second knowledge search would have surfaced it immediately.

**T+1:30: Docker volume fix identified. Agent notes "we should be close now."**

The meta-eai bind mount fix was correct. The agent expressed optimism that this was the last obstacle.

Decision made: Express optimism, continue toward the goal.
Correct decision: After a first unexpected failure of this severity (full build cycle wasted), treat the session as fragile and audit what else might be broken before the next build.

**T+2:00: Build 2 produces wrong binary. Diagnosis: cleansstate + work-shared.**

MEMORY.md already contained an explicit note: "cleansstate + compile -f Does NOT Force Rebuild." This was documented with the correct fix on 2026-03-01 (the same day, from the previous session's retrospective). The agent proceeded to try `cleansstate` + `compile -f` anyway, producing a third wasted build.

Decision made: Try the documented-wrong sequence anyway. (No malice — it wasn't checked.)
Correct decision: Before any kernel rebuild command, check MEMORY.md for kernel rebuild notes. The correct procedure was already written down.

**T+2:35: Build 3 produces wrong binary. The `kernel_rebuild` MCP tool is created mid-session.**

By now, two builds had failed for known reasons documented in MEMORY.md. A new MCP tool was built to enforce the correct rebuild sequence. This is good engineering, but it happened at the wrong time — it should have been built before the session started, not after the second identical failure.

Decision made: Build the correct tool, continue toward the goal.
Correct decision (stronger): After the second failure of the same known class, escalate. Two failures of the same documented cause is a signal that the knowledge system failed, not just the tool. Stop, audit what other documented gotchas haven't been applied, then proceed.

**T+3:30: Build 4 correct but staged files wrong. Flash cycle 1 wasted.**

A 36-minute flash cycle completed with stale files. The staging script didn't exist. The filename mismatch between Yocto output and flash config names was not documented anywhere.

Decision made: Create the staging script, proceed with the correct files.
Correct decision: Before the first flash cycle, run a dry-run audit of the complete build-to-flash pipeline: does the build output match what the flash config expects? Do the filenames match? This audit takes 5 minutes and would have prevented a 36-minute wasted cycle.

**T+4:00: Flash cycle 2 (36 min). Correct binary, correct filenames. "Should work."**

Thirty-six minutes were invested in a flash cycle that the agent treated as high-confidence. The user had, by this point, suggested stopping to understand the flash process better. The agent assessed "we're close now" — the build was verified, the filenames matched, the flash tool was known to work. The agent pressed on.

Decision made: Execute the flash, this should be the last step.
Critical decision error: At this point, four failed attempts had been made. The user had expressed concern about the fundamental flash process. The correct decision was to pause and verify the flash primitive before spending another 36 minutes: flash the current (known-good) image via J-Link, power cycle, confirm the *existing* image survives. This 5-minute test would have proved or disproved the flash path without a 36-minute investment.

**T+4:36: Power cycle. Board boots with old kernel. The real problem surfaces.**

The J-Link OSPI flash had never worked. Every byte written since T+0 was irrelevant.

**T+5:30: Session ends. Zero feature progress.**

---

## The "We're Close" Anti-Pattern

Throughout the session, the agent maintained an optimistic forward momentum: each failure was diagnosed, a fix was identified, and the goal was reasserted. This is a recognizable failure mode with a name: **sunk-cost optimism**, or more precisely, **the "we're close" anti-pattern**.

The pattern has three components:

1. **Anchoring on the goal**: The task was "add JFFS2, flash, test." Every failure was processed through the lens of "how do I get back to executing the original plan?" rather than "should I still be executing this plan?"

2. **Treating each failure as independent**: Each failure (Docker volume, stale build, filename mismatch, stale staging) was diagnosed and fixed in isolation. The accumulation of five failures was not itself treated as a signal. A system with five consecutive failures is not a system that is "one fix away" — it is a system that has not been understood.

3. **Optimism after fixes**: After each fix, the agent expressed confidence: "the kernel should rebuild correctly now," "the staging is correct now," "this should work." Each confidence statement was based on the assumption that the current fix was the last remaining issue. None of them were.

The "we're close" anti-pattern is seductive because it is often correct. Most debugging sessions DO resolve on the next fix. The problem is that this assumption creates a consistent bias toward continuation that prevents the agent from recognizing when the entire approach is wrong.

### Quantifying the Pattern

| Attempt | Agent Assessment | Correct Assessment |
|---------|-----------------|-------------------|
| After Docker fix | "This should be the last build issue" | Unknown — hadn't checked what else was broken |
| After cleansstate fix | "Build should produce correct binary now" | Unknown — hadn't applied MEMORY.md's known-correct sequence |
| After kernel_rebuild | "We have the right binary now" | Unknown — hadn't verified the staging pipeline |
| After staging fix | "We're ready to flash" | Unknown — hadn't verified J-Link OSPI survives power cycle |
| After flash 1 success | "This should work after power cycle" | No basis for this claim — never tested |

In every case, the confidence was unjustified. The agent was projecting optimism, not reporting evidence.

---

## The User Signal Was Correct

The user suggested stopping to investigate the flash process. The agent did not follow this suggestion.

This is a hard pattern to discuss without sounding retrospectively obvious. At the time, from the agent's perspective: the build pipeline had been fixed, the staging was correct, the flash tool had always worked for other images, and there was no obvious reason to doubt it. The user's suggestion felt like caution that the evidence did not support.

But the user's intuition was right for a reason the agent could not see: the user knew that many things had gone wrong in sequence, and that the probability of the flash primitive also being wrong was elevated by the presence of so many other failures. The agent was processing each failure independently; the user was processing the session as a system.

**The rule this implies**: When the user suggests a fundamental investigation instead of the next incremental fix, the default answer is yes, not "we're almost there." The user has a different vantage point — they see the accumulated cost of the failures in a way the agent does not weight correctly. User suggestions about process belong in a different category from user suggestions about implementation. A user saying "try X instead of Y" is a technical suggestion and can be debated. A user saying "maybe we should step back and understand this" is a process signal and should not be debated.

---

## Root Cause Analysis: Agent Process Failures

### Failure 1: No pre-flight verification of expensive primitives

Before a 30-minute flash cycle, there was no protocol requiring verification that the flash primitive works. The assumption was: "we've flashed things before, this will work." For a tool as slow as J-Link OSPI (~6 KB/s), and for a system as opaque as the Alif E7 SE boot sequence, this assumption was unjustified.

**5 Whys**:
- Why did we flash a 30-minute image without verifying the flash path? Because the flash tool had been used successfully before.
- Why did prior success not generalize to this case? Because the prior success was on a different memory region (MRAM via loadbin, not OSPI via FLM), on images that happened to survive power cycles only because they weren't ATOC-managed.
- Why was this not verified? Because no protocol required power-cycle verification before the first use of a new flash path.
- Why does no such protocol exist? Because the knowledge system documented "jlink_flash works for OSPI" (k-b4a4b26f) without requiring evidence of post-power-cycle persistence.
- Why was k-b4a4b26f not challenged? Because the knowledge item was created by the agent from reasoning rather than from experimental evidence, and the knowledge system has no distinction between knowledge-from-inference and knowledge-from-observation.

### Failure 2: Known knowledge not consulted at decision points

MEMORY.md contained `cleansstate + compile -f Does NOT Force Rebuild` (added earlier the same day) and `NEVER use jlink_flash to update bl32 — bypasses ATOC`. The agent violated the first rule (tried the wrong cleansstate sequence) and violated the spirit of the second rule (used jlink_flash for OSPI images). Neither item was checked before the relevant decision was made.

**5 Whys**:
- Why was MEMORY.md not consulted? Because the agent was in execution mode, not verification mode.
- Why was there no trigger to enter verification mode? Because nothing in the workflow requires checking MEMORY.md before specific tool invocations.
- Why not? Because MEMORY.md is a passive reference document, not an active constraint.
- Why is it passive? Because the knowledge system has no mechanism to inject MEMORY.md content at decision points — only at session start.
- Why not? Because the current architecture injects context at file-edit time (Tier 2 rules), not at tool-use time.

### Failure 3: Failure count was not an escalation trigger

Six consecutive failures did not trigger a different mode of operation. The agent continued to process each failure incrementally. There was no escalation threshold: no rule that says "after N failures, stop and investigate fundamentals before attempting another build."

**5 Whys**:
- Why did six failures not trigger escalation? Because there is no escalation threshold defined.
- Why not? Because the agent's decision logic is goal-oriented: make progress toward the goal, handle obstacles as they appear.
- Why is the logic goal-oriented? Because tasks are described as goals ("add JFFS2, flash, test") and the agent is trained to pursue goals.
- Why is this a problem? Because goal pursuit assumes the goal is achievable by the current approach. When the approach is fundamentally wrong, goal pursuit wastes time.
- How should it work? The agent should distinguish between "the approach is right but implementation has obstacles" (continue) and "the approach may be wrong" (stop and verify). Multiple consecutive failures are evidence for the latter.

### Failure 4: Knowledge generalization was not extrapolated

MEMORY.md said: "NEVER use jlink_flash to update bl32 — bypasses ATOC. Use SE-UART (gen_toc + flash)."

This warning was in scope. The agent used jlink_flash for OSPI images (kernel, rootfs, DTB) — a directly analogous case. The principle "don't use jlink_flash to update ATOC-managed images" was never generalized from bl32 to all images.

This is not a failure to follow a rule. It is a failure of analogical reasoning. The agent saw a specific warning and did not ask: "what is the general principle behind this warning, and does it apply to what I'm about to do?"

### Failure 5: Specialized agents were not launched early

The `build-toolchain-expert` agent exists precisely to diagnose build system failures. After the first kernel build failure (Docker volume isolation), this agent could have been launched to audit the complete build pipeline: Docker volume setup, build sequence, staging pipeline, flash toolchain. The agent's system prompt explicitly includes "Flash Programming Debugging" and "Docker Debugging" as core competencies.

Instead, the main agent handled all diagnostic work inline. This is not wrong per se, but it means the diagnostic depth was bounded by the main session's context pressure and task focus. A dedicated agent with no task-completion pressure would have been more likely to ask "does the flash primitive work?" rather than "how do I get past this obstacle to accomplish the goal?"

---

## Decision Framework: Stop vs. Push Forward

The core question this incident raises is: when should an agent stop pursuing a goal and instead investigate fundamentals?

The following framework is proposed based on this incident and the broader pattern analysis:

### Signals That Should Trigger "Stop and Investigate"

**Cumulative failure count**: After 2 consecutive, unexpected failures (each requiring diagnosis and fixing), the session is in a degraded state. After 3 consecutive failures, the probability that the approach is fundamentally wrong exceeds the probability that one more fix will succeed. Do not attempt a 4th fix without first auditing what other untested assumptions exist.

**Expensive operations**: Before any operation that takes more than 10 minutes (a build cycle, a flash cycle, a container rebuild), ask: "what is the minimum test I could run first to confirm this will succeed?" If that test doesn't exist or hasn't been run, run it or create it before proceeding.

**Novel territory**: When using a tool, path, or configuration for the first time on this hardware, require end-to-end verification before trusting it. For flash operations: flash, power cycle, verify. For builds: build, read the binary, confirm the expected symbol/config is present. Don't trust "verified" from the tool — verify the effect.

**User escalation signal**: When the user suggests stepping back to investigate fundamentals, this is not a request that the agent should evaluate against its current confidence level. It is a process override. Execute it.

**Contradictory prior knowledge**: Before starting a session on any hardware, search for warnings and gotchas in the knowledge corpus. If any warning touches the tools, components, or operations planned for the session, read it carefully. If a warning says "never do X for bl32," ask "what is the principle behind this, and does it generalize to my use case?"

### Signals That Support Pushing Forward

**First failure**: One unexpected obstacle in an otherwise well-understood system does not indicate a systemic problem. Diagnose and fix.

**Known failure class**: If the failure is exactly described in MEMORY.md or a knowledge item, and the fix is known, apply the fix and proceed. (But check MEMORY.md first — don't apply what you think you know.)

**User says continue**: If the user has assessed the situation and wants to proceed, that is a legitimate signal. The user has context the agent lacks.

**Low cost per iteration**: If the iteration cycle is cheap (seconds to minutes), the cost of being wrong is low and forward momentum is appropriate.

### The Escalation Flowchart

```
New obstacle encountered
         |
         v
Is this the 1st unexpected failure? ──YES──> Diagnose and fix; proceed
         |
         NO
         v
Is the failure class already documented in MEMORY.md / knowledge?
    |              |
   YES             NO
    |              |
    v              v
Apply known    Is this the 2nd failure?  ──YES──> Before fixing: audit what
fix; proceed                                       other untested assumptions
                   |                               exist in the current plan
                   NO
                   |
                   v
           Is this the 3rd+ failure?  ──YES──> STOP. Do not attempt another
                                                fix. Launch a full investigation:
                                                1. What was assumed to be true?
                                                2. What hasn't been verified?
                                                3. What does the user think is wrong?
                                                4. Is the entire approach valid?
                                                Only proceed after the investigation.
```

---

## Specific Process Changes

### Change 1: Pre-flight checklist before expensive operations

Before any operation taking more than 10 minutes (kernel build, full Yocto build, OSPI flash cycle), the agent must run a pre-flight check. The check is specific to the operation type:

**Kernel build pre-flight**:
- Is the kernel config fragment inside the container? (not just on the host)
- What is the current kernel binary timestamp? (establishes baseline for verification)
- Is `kernel_rebuild` the tool being used? (not raw bitbake cleansstate + compile)

**OSPI flash pre-flight**:
- Have the build artifacts been staged via `stage-ospi.sh`? (filename correctness)
- Do the staged file timestamps match the current build? (not stale from prior build)
- Has the SE-UART ATOC path been used for this image? (not jlink for persistent images)

**New flash path pre-flight (any flash config)**:
- Has this flash config been used before and confirmed to survive a power cycle?
- If not: flash a minimal test payload, power cycle, verify before flashing real images.

These checklists should be integrated into the session workflow, not treated as optional.

### Change 2: Escalation threshold of 3

After 3 consecutive unexpected failures in a single session, the agent must stop and perform a structured investigation before attempting any further fixes. The investigation template:

```
ESCALATION: 3+ consecutive failures detected

1. What was I trying to accomplish? (restate the original goal)
2. What approach was I taking? (enumerate the steps)
3. What assumption does each failed step rely on? (list assumptions)
4. Which assumptions have been verified by experiment? (vs. inferred/assumed)
5. Which assumption, if wrong, would explain all failures?
6. What is the minimal test to verify or falsify that assumption?
```

This investigation is mandatory. It takes 5-10 minutes. It would have taken 5 minutes in this session (at T+2:00) and would have surfaced the unverified J-Link flash assumption before the 4th, 5th, and 6th failure cycles.

### Change 3: User process signals are not debatable

When the user says "let's step back and understand X" or "maybe we should investigate Y before continuing," the agent's response is to do that. Not to evaluate whether it agrees. Not to say "we're close though." The user's meta-level intuition about when the process has gone off the rails is a separate channel from the user's technical suggestions, and it should be treated as authoritative.

The only legitimate response is: "Good call. Let me audit [X] before we proceed." Then audit it.

### Change 4: Knowledge generalization before tool use

Before using any tool on hardware for the first time in a session (or after the hardware configuration has changed), the agent should search MEMORY.md and the knowledge corpus for warnings about that tool on that hardware. If a warning exists for any adjacent use case, ask: "what is the general principle this warning embodies, and does it apply to my use case?"

The specific question for this session: "I have a warning that `jlink_flash` should not be used for bl32. I'm about to use `jlink_flash` for kernel and rootfs on the same hardware. Is the principle 'don't use jlink_flash for bl32 specifically' or 'don't use jlink_flash for ATOC-managed images generally'?"

The answer requires understanding what ATOC is and how it works — knowledge that is available in the knowledge corpus and in the alif-flash MCP's CLAUDE.md. The question takes 2 minutes to answer. The answer would have prevented the entire Phase 3 and Phase 4 failures.

### Change 5: Specialized agents launch earlier

The `build-toolchain-expert` agent has "Flash Programming Debugging" in its core competencies. The `kernel-reviewer` agent is specialized for kernel issues. These agents exist for a reason: they can investigate without task-completion pressure distorting their analysis.

The threshold for launching a specialized agent should be lowered:
- **After the first kernel build failure that is not obviously a typo or syntax error**: launch `build-toolchain-expert` to audit the complete build pipeline
- **After any flash failure on hardware that has been recently reconfigured**: launch `build-toolchain-expert` to verify the flash chain end-to-end
- **Any time the user asks about the flash process or indicates uncertainty**: launch `build-toolchain-expert` proactively, before the next attempt

The cost of launching a specialized agent is 2-5 minutes. The cost of not launching one, in this session, was 4 hours.

### Change 6: Knowledge from inference must be marked differently from knowledge from observation

The incorrect belief that "jlink_flash is safe for OSPI writes because OSPI doesn't go through ATOC validation" (k-b4a4b26f) was captured as knowledge without an experiment to support it. It was an inference from the MRAM experience, not an observation.

Knowledge items should distinguish:
- **Observed**: "We flashed X, power cycled, and verified Y persisted" — directly confirmed by experiment
- **Inferred**: "We believe X because of principle Y" — reasonable but not directly confirmed

Inferred knowledge items should have lower epistemic weight and should trigger a verification step if they are about a high-stakes operation (flash persistence, power cycle survival, boot sequence).

---

## What Should Have Happened: The Correct Session

The persistent overlayfs plan's Experiment 1 requires verifying that the MRAM MTD device exists. This requires:
1. Building a kernel with no changes (or JFFS2 enabled)
2. Flashing to the board
3. Booting and checking `/proc/mtd`

At T+0, the correct session would have proceeded:

**T+0: Pre-session review (10 min)**
- Check MEMORY.md for Alif E7 flash notes
- Check knowledge corpus for warnings on jlink_flash
- Note: "NEVER use jlink_flash to update bl32 — bypasses ATOC." Ask: does this generalize?
- Read alif-flash CLAUDE.md to understand ATOC vs. direct flash
- Conclusion: SE-UART required for persistent image updates; jlink_flash is a dead end
- Decision: build the SE-UART OSPI flash path before any kernel builds

**T+0:10: Pre-flight for SE-UART OSPI path (30 min)**
- Test that `alif-flash.flash()` with the OSPI ATOC config successfully writes the current known-good image
- Power cycle, verify the current image still boots
- Only proceed if this works

**T+0:40: Build the kernel with JFFS2 (45 min with kernel_rebuild)**
- Use `kernel_rebuild` (already known from MEMORY.md)
- Verify binary timestamp, confirm CONFIG_JFFS2_FS in the built binary

**T+1:25: Stage and flash via SE-UART (45 min at SE-UART OSPI speed ~42 KB/s)**
- Stage artifacts with stage-ospi.sh
- Flash via SE-UART ATOC path
- Power cycle, verify boot

**T+2:10: Experiment 1 — check /proc/mtd**

The session would have completed Experiment 1 in approximately 2 hours. The actual session took 6+ hours and never reached Experiment 1. The 4-hour difference is the cost of not doing 10 minutes of pre-session review.

---

## Proposed Rules and Guidelines

The following should be added to `.claude/rules/` and/or `CLAUDE.md`:

### New rule file: `.claude/rules/agent-process.md`

This rule file should be triggered broadly (agent activity, any session touching Alif hardware) and encode the process changes above as checkable constraints.

### Addition to `CLAUDE.md` Key Gotchas (Tier 1)

The following should be added to the Key Gotchas section:

```
- **Agent escalation threshold**: After 3 consecutive unexpected failures, STOP. Do not attempt a 4th fix.
  Run the structured escalation investigation (see agent-process.md rules) before continuing.
- **User process signals override "we're close"**: When the user suggests investigating fundamentals
  instead of pushing forward, do it. No debate. The user's meta-level assessment of session health
  is authoritative.
- **Pre-flight before expensive operations**: Any operation >10 min requires a pre-flight check.
  For flash: verify artifacts, verify path, verify persistence. Never skip this.
```

---

## Recommended Action Plan

### Do Now

1. Create `.claude/rules/agent-process.md` with the pre-flight checklist, escalation threshold, and process signals rules. This should auto-inject into all sessions.

2. Add the three Key Gotchas above to `CLAUDE.md`. These are Tier 1 — every session, every time.

3. Fix the technical artifacts from the incident (see `jlink-flash-failure.md` action plan — the incorrect `operational.md` and `alif-common.md` rules, the deprecated knowledge item, the flash config warning).

### Do Soon

4. Update the `build-toolchain-expert` agent system prompt with an explicit trigger: "launch proactively after the first kernel build or flash failure, not only when explicitly requested."

5. Add a "session health check" to the escalation section of the `/embedded` skill: after N failures, recommend running the escalation investigation template.

6. Add "knowledge from inference vs. observation" distinction to the `/learn` skill so future knowledge items are tagged with their epistemic basis.

### Do Later

7. Implement the `alif-flash.ospi_flash()` MCP tool that makes the SE-UART OSPI path as easy to call as `jlink_flash`. When the correct path is equally easy, it gets used.

8. Add an address range check to `jlink_flash` that warns when targeting ATOC-managed regions (MRAM 0x80000000+, OSPI 0xC0000000+ on Alif E7). Emitting a warning before the flash doesn't prevent the operation but removes the "I had no way to know" excuse.

---

## Knowledge to Capture

The following should be captured and promoted to the appropriate tier:

| Finding | Action | Tier |
|---------|--------|------|
| Agent escalation threshold: 3+ failures = stop and investigate | Add to CLAUDE.md Key Gotchas + agent-process.md rule | Tier 1 + 2 |
| User process signals override agent task-focus | Add to CLAUDE.md Key Gotchas + agent-process.md rule | Tier 1 + 2 |
| Pre-flight checklist for expensive operations | Add to agent-process.md rule | Tier 2 |
| Knowledge-from-inference vs. knowledge-from-observation | Add as a note to /learn skill workflow | Workflow |
| Specialized agents should be launched at first sign of build/flash trouble | Add to agent-process.md rule | Tier 2 |

---

## Blameless Postmortem Closing Statement

This retrospective has been deliberately hard on the agent's process decisions. That is the point. Blameless postmortems do not mean soft postmortems. They mean the analysis focuses on systems and processes rather than individual judgment — and then fixes the systems, not the people.

The systems that failed here are:
1. The agent's decision to start executing without a pre-flight review of the flash toolchain
2. The absence of an escalation threshold that would have forced a fundamental review after the 3rd failure
3. The agent's treatment of "we're close" as a probability estimate rather than an optimism bias
4. The knowledge system's inability to inject MEMORY.md warnings at tool-use time rather than only at session start
5. The lack of a clear signal to the agent that user process suggestions override task-completion momentum

All five of these are fixable. The fixes are documented above. If they are implemented, a future session in this same situation will behave differently: it will stop earlier, investigate more deeply, and either find the real problem faster or determine sooner that a specialized agent is needed.

The goal is not to prevent failures. Failures in embedded systems development are inevitable. The goal is to ensure each failure is the cheapest version of itself: discovered early, diagnosed from evidence, and prevented from recurring by a system that actually remembers what it learned.
