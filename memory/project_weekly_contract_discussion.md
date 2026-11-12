---
name: project-weekly-contract-discussion
description: "Decided 12-nov-2026: the weekly contract is a TEMI issue labelled Weekly Contract; Quicksave's card, skill and morning job must read it from Linear instead of the vault file"
metadata:
  node_type: memory
  type: project
  modified: 2026-11-12T08:30:00.000Z
---

On 12-nov-2026 Alejandro decided the weekly contract lives in Linear: an open TEMI issue with the label `Weekly Contract`, objectives under `## Objectives` with their issues linked as `related`. It is made on Tuesday afternoon after the Spain area weekly, in the same session as the review of the whole pile (every open issue gets a date, Backlog or canceled). The SFA comes out of it. Shape: the vault's `Claude/templates/weekly-contract.md`.

**Why:** Linear is the only source of truth for the plan, and the vault file stayed half empty (Progreso, Material del SFA) once the Daily stopped.

**How to apply:** pending code: `WeeklyContract.swift` (card), the morning job prompt in `Morning.swift` and `.claude/skills/quicksave-main-quest/SKILL.md` still read `~/vault/Journal/*Weekly Contract.md`. Switch them to Linear. Building the contract from inside the app is still to design.
