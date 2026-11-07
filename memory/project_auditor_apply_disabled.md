---
name: project-auditor-apply-disabled
description: "The vault's scheduled auditor-apply Orca automation was disabled on 6-nov-2026 so the Quicksave inbox can replace it; until the inbox exists nothing executes approved triage items"
metadata:
  node_type: memory
  type: project
  originSessionId: 278d3528-4e65-4795-a61c-61b4756cdac9
  modified: 2026-11-06T22:25:41.730Z
---

On 6-nov-2026 Alejandro asked to switch off the `auditor-apply` Orca automation (id 856c6a9a-1eee-4701-a346-acf884d83240), because the Quicksave inbox will apply what he decides. Disabled with `orca automations edit <id> --disabled`, not removed. The auditor sweeps (`auditor-deep`) stay on and keep filing Triage.

**Why:** two appliers would run the same approved item twice.

**How to apply:** until the inbox ships, approved items (Todo) wait for a manual `/auditor apply` or a dictated triage in the chat. If he asks why items are not executing, this is why. To undo: `orca automations edit <id> --enabled`. The inbox design is in `docs/inbox.md`.
