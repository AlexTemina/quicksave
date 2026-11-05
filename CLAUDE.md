# Quicksave

A native macOS app that shows Alejandro's day, read live from Linear. Built from zero, one feature at a time, each one discussed before any code.

Nothing here is inherited from older setups (Save Point, the vault, global rules). A rule exists only if it is written in this file.

## Rules

- Talk to Alejandro in Spanish. Anything that leaves (Linear, GitHub, Slack, email) is in English, with no em-dashes.
- Never publish anything: no Linear comments, Slack messages, GitHub comments or mail. Drafts only, which he posts himself.
- Never `git commit` or `git push` unless he asks in the same turn.
- Talk about the product, never the code. Alejandro does not want to see Swift, file names or diffs: report what the app does, what changed for him, and what he has to decide.
- Every code (issue, PR) carries a 2-3 word tag of what it is: `ES-12785 (30-day invitations)`, never a bare id.
- The app's interface is in English only, for now.
- Linear is the source of truth for tasks and their state. Quicksave reads it and never keeps its own copy of a task's state.

## Docs

- [Main Quest](docs/main-quest.md): what it is and how it lives in Linear.
- [Writing in Linear](docs/linear-writing.md): how Quicksave writes what it owns there.

## Layout

- `app/`: the macOS app (Swift).
- `.claude/skills/`: commands, always named `quicksave-<command>`.
- `memory/`: this project's Claude memory, versioned here. `MEMORY.md` is its index.
- `docs/`: how Alejandro organises his work and how Linear is kept up to date.
- `scripts/claude.sh`: the only way to start a session on this repo.
