# Multi-Agent Deliberation System

**Status**: Complete

## Summary

Multi-agent debate system for complex decisions. Three agents (advocate, critic, synthesizer) debate via shared log files on disk, orchestrated by `/deliberate` skill.

## Files

| File | Status |
|------|--------|
| `claude-config/agents/advocate.md` | Done |
| `claude-config/agents/critic.md` | Done |
| `claude-config/agents/synthesizer.md` | Done |
| `claude-config/commands/deliberate.md` | Done |
| `claude-config/CLAUDE.md` | Updated |
| `CLAUDE.md` | Updated |
| `.claude/debates/` | Created |

## Verification

- [x] Test `/deliberate` on a real question (alif OSPI pass 1 hang diagnosis)
- [x] Verify debate log created and all agents invoked (2 rounds advocate + critic, 1 synthesizer)
- [x] Verify synthesis produced and decision recorded

## Implementation Notes

- First real use saved a 13-minute reflash cycle with a 30-second J-Link diagnostic
- Critic caught two code-verified factual errors in advocate's Round 1 (marker2 address, error path flow)
- Round 2 revision addressed all issues; Round 2 critique found additional edge cases
- Synthesizer correctly predicted the most likely outcome
- Debate log at `.claude/debates/2026-03-01-alif-ospi-pass1-hang.md`
