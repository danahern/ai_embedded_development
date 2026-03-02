---
paths: ["plans/**"]
---
# Plan Lifecycle Rules

- **Mark plans Complete when all verification steps pass.** After finishing implementation, check the plan's Verification section. If every item is confirmed, update `Status: In-Progress` to `Status: Complete` and fill in the Solution and Implementation Notes sections.
- **Never mark Complete with open items.** If any verification step fails or was skipped, the plan stays In-Progress.
- **Update incrementally.** When you discover gotchas, change approach, or defer scope during implementation, update the plan file immediately — not after the fact.

## Power-Cycle Verification for New Flash Paths

Before committing any new flash config (`*-jlink.json`, `*-atoc.json`, etc.):
1. Flash a known test payload (e.g., kernel with unique version string)
2. Verify the payload reads back correctly
3. Power cycle the board
4. Verify the payload is still present and functional post-power-cycle
5. Only commit the config after step 4 passes

Any plan involving a new flash path must include this protocol in its Verification section.
