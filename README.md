# Quicksave

A native macOS app that shows the day, read live from Linear. Linear is the source of truth: the app never keeps its own copy of a task's state. It reads Linear, and writes to it only from the inbox, when you decide a card.

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

### Inbox

- A deck of cards with everything waiting for a decision: the auditor's Triage items and the vault's open pull requests. One card at a time, with what happened, what will be done and why.
- Keys on the left hand: `D` accepts (merges a pull request), `E` accepts with a correction, `A` rejects, `Q` marks it already done, `space` leaves it for later, `⌘Z` undoes.
- A decision on a Triage card is written to Linear at once. A decision on a pull request waits until Apply.
- `Apply` (`⌘⇧↩`) merges or closes the pull requests, then starts an agent for the accepted items. Code work is handed to a second agent that runs inside the item's worktree, never pushes, and leaves its summary in the worktree's Orca comment.
- A panel shows what each item ended in, and the drafts the agents left.
- The agents run with a short list of allowed actions: they cannot post comments or messages.

### Drafts

- A tab with the text the agents leave for you to post yourself: where it goes, a note on what to do, a copy button and a link to the place.
- Select the ones already posted and archive them. Archived drafts can be restored.

### Menu bar and icon

- The menu bar shows the crystal in color and pieces done over total, like `0/2`.
- Its menu shows the Main Quest's title, the next piece and pieces done, how many cards wait in the inbox, and buttons for the board, Settings and refresh.
- The app has its own crystal icon in pixel art.

### Staying fresh

- The app refreshes with a button, when the window gets focus or the menu opens, and automatically every minute.

### Settings

- The Linear API key is pasted once and stored encrypted in a local database, tied to this Mac.

## Commands

- `/quicksave-main-quest`: proposes the day's Main Quest from the weekly contract and Linear, waits for an ok, and then creates it or moves the open one.

## Not built yet

- Agent status on cards (Working, Needs you, Done), last reply, summary, sending a message and starting a new agent.
- A button to run the auditor's sweep from the inbox, and cards for items that came back needing you.
- The morning contract that fills Side Quests.
- A "No QA" warning in the detail when an issue does not follow the template. This one is proposed, not decided.

## Docs

- [Main Quest](docs/main-quest.md): what it is and how it lives in Linear.
- [Writing in Linear](docs/linear-writing.md): how Quicksave writes what it owns there.
- [The board](docs/board.md): what the app shows and how it stays fresh.
- [The inbox](docs/inbox.md): the deck, its decisions, undo and apply.
- [Drafts](docs/drafts.md): where the text you post yourself lands.
- [Background agents](docs/background-agents.md): how the app starts agents, with their permissions.
- [Design system](docs/design-system.md): tokens and components.

## Development

- Start a Claude session on this repo with `scripts/claude.sh`, never with plain `claude`: it uses a clean profile so no outside rules, skills or memory load.
- `scripts/bundle.sh` builds the app, installs it in `/Applications` and relaunches it.
