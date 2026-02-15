---
paths: ["plans/**"]
---
# Plan Lifecycle Rules

- **Mark plans Complete when all verification steps pass.** After finishing implementation, check the plan's Verification section. If every item is confirmed, update `Status: In-Progress` to `Status: Complete` and fill in the Solution and Implementation Notes sections.
- **Never mark Complete with open items.** If any verification step fails or was skipped, the plan stays In-Progress.
- **Update incrementally.** When you discover gotchas, change approach, or defer scope during implementation, update the plan file immediately — not after the fact.
