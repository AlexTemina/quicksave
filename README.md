# Quicksave

A native macOS app that shows the day, read live from Linear. Linear is the source of truth: the app only reads it and never keeps its own copy of a task's state.

## The system

- **Main Quest:** the minimum that makes the day a good day. It has one goal, takes one or two days, and only one is open at a time.
- **In Linear:** it is a TEMI issue with the `Main Quest` label. Its due date is the planned end, and past that date it has slipped.
- **Pieces:** the real issues that make up the Main Quest, linked as `related` and done in order, one after another.
- **Side quests:** work that does not serve the Main Quest's goal. What goes there will come from a morning contract, which is not designed yet.

See [Main Quest](docs/main-quest.md) for the full rules.

## Features

### Board

- A kanban for the Main Quest with one column per Linear state, in Linear's colors. Empty columns collapse to a thin strip.
- A header with the Main Quest's title, its "done" sentence, its state, pieces done over total, and its due date.
- A Side Quests area below it, empty until the morning contract exists.

### Cards

- Each card shows the issue code, its tag and today's step.
- Each card shows its PRs with live CI: open green, CI failing red, merged purple, draft grey, closed brown.
- An "Agent" tag appears when a Claude agent is live in the issue's Orca worktree.
- On hover, one button opens the issue in Linear and another goes to its worktree in Orca.

### Piece detail

- Clicking a card opens the issue read through the issue template: Context with the Goal, Actions, Watch out and QA.
- Everything else is folded under More.

### Going to Orca

- With a live agent, the button brings that agent's tab forward.
- With a linked worktree and no agent, it brings the first open terminal forward, or opens a new one there.
- With no linked worktree, the button is off.

### Menu bar and icon

- The menu bar shows the crystal in color and pieces done over total, like `0/2`.
- Its menu shows the Main Quest's title, the next piece and pieces done, with buttons for the board, Settings and refresh.
- The app has its own crystal icon in pixel art.

### Staying fresh

- The app refreshes with a button, when the window gets focus or the menu opens, and automatically every minute.

### Settings

- The Linear API key is pasted once and stored encrypted in a local database, tied to this Mac.

## Not built yet

- Agent status on cards (Working, Needs you, Done), last reply, summary, sending a message and starting a new agent.
- `/quicksave-morning`: creating the day's Main Quest and, later, the morning contract that fills Side Quests.
- A "No QA" warning in the detail when an issue does not follow the template. This one is proposed, not decided.

## Docs

- [Main Quest](docs/main-quest.md): what it is and how it lives in Linear.
- [Writing in Linear](docs/linear-writing.md): how Quicksave writes what it owns there.
- [The board](docs/board.md): what the app shows and how it stays fresh.
- [Design system](docs/design-system.md): tokens and components.

## Development

- Start a Claude session on this repo with `scripts/claude.sh`, never with plain `claude`: it uses a clean profile so no outside rules, skills or memory load.
- `scripts/bundle.sh` builds the app, installs it in `/Applications` and relaunches it.
