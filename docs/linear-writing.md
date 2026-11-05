# Writing in Linear

How Quicksave writes issue descriptions it owns, like the Main Quest. A reply to a person is a message, not a record, and does not follow this.

## Style

- Bullets, not paragraphs. One line per bullet. If a bullet wraps twice, split it.
- Link every mention inline: issue, PR, doc, thread.
- Every code carries a 2-3 word tag of what it is: `ES-12785 (30-day invitations)`, never a bare id.
- Short, complete sentences. No filler, no telegraphic fragments.

## Fields

- Native fields are never repeated in the description: priority, due date, state, labels.
- Every task has a due date. Missed dates are moved, never cleared.
- Related issues are relations, not text mentions.
- An issue that asks for work carries a `## QA` section with observable checks and real inputs.
- The description is the current truth, rewritten as if it had always been known. No "it used to say X".

## Comments

- Default: no comment. Quicksave never posts one; at most it drafts one for Alejandro.
- A comment is worth drafting only when the description changed, or a decision was taken about the task (parked, dropped, split, blocked).
- Never the mechanics: CI, PRs, commits, reviews, "starting on this".
