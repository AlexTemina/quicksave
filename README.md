# Quicksave

A native macOS app that shows the day, read live from Linear. Linear is the source of truth: the app never keeps its own copy of a task's state. It reads Linear, and writes to it only from the inbox, when you decide a card, and from the morning, when you approve the plan.

## The system

- **Main Quest:** the minimum that makes the day a good day. It has one goal, takes one or two days, and only one is open at a time.
- **In Linear:** it is a TEMI issue with the `Main Quest` label. Its due date is the planned end, and past that date it has slipped.
- **Pieces:** the real issues that make up the Main Quest, linked as `related` and done in order, one after another.
- **Side quests:** the other work that fits today, beyond the Main Quest. Only what fits, not everything open. They are part of the plan, so they live in the Main Quest's description in Linear, under `## Side quests`.
- **Collectibles:** reading and tiny things, no agent and no decision. Issues with the `collectible` label.

See [Main Quest](docs/main-quest.md) for the full rules.

## Features

### Board

- A kanban for the Main Quest with one column per Linear state, in Linear's colors. Empty columns collapse to a thin strip.
- A header with the Main Quest's title, its "done" sentence, its state, pieces done over total, and its due date.
- Side Quests below it, on the same kind of board: the side quests the plan lists, each with its state, due date and why it is in today. Closed ones are crossed out. "Add to today" picks one of your open issues, in queue order, and adds it to the plan; hovering one lets you take it out. The issue itself never changes.
- Collectibles in a column down the right side, next to the Main Quest and the side quests: every open issue of yours with the `collectible` label, by due date, overdue in red.

### Progress

- A Day bar at the top: every piece in gold and every side quest in green, filling as they close, "Day cleared" at the end.
- A bar for the Main Quest, one for the side quests, and a small one on each piece for the Actions ticked in its issue. Bars bounce when they move and glow when full.

### Cards

- Each card shows the issue code, its tag and today's step.
- Each card shows its PRs with live CI: open green, CI failing red, merged purple, draft grey, closed brown.
- The card takes the color of its agent's state, read from Orca every few seconds: yellow working (breathing), green waiting for you, grey idle, red error. Hovering shows its last reply; the detail shows it in full.
- On hover, one button opens the issue in Linear and another goes to its worktree in Orca.

### Piece detail

- Clicking a card opens the issue read through the issue template: Context with the Goal, Actions, Watch out and QA.
- Everything else is folded under More.

### Going to Orca

- With a live agent, the button brings that agent's tab forward.
- With a linked worktree and no agent, it brings the first open terminal forward, or opens a new one there.
- With no worktree but an agent tab named after the issue, it brings that tab forward.
- With nothing, the button is Start: `/start-task` runs in the background and opens the worktree and the agent in Orca. Work with no code gets an agent in the vault, in Orca, named after the issue.

### Morning

- A "Start the day" button on the board, big when no Main Quest is open, and in the menu bar. It opens a panel.
- It warns when the inbox has cards to decide and keeps the plan off until it is clear, with a "Continue anyway".
- A box for your comments on the day, then an agent proposes the Main Quest and the side quests that fit: goal, done, pieces in order, due date, why, what was left out, meetings and failed sources.
- Correct it as many times as you want; approving writes it to Linear.
- Five games for the standup's simile, never one already used, plus your X/5. The log of every game played is in the panel, imported once from the vault.
- The standup is written with the chosen game and lands in Drafts, linked to today's standup thread.

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

### Hover cards

- Resting the pointer on any link, anywhere in the app, shows a small card. Linear issues and GitHub pull requests show their state, title, key facts and the start of the description; any other page its title and summary. Slack links do not have one yet.

### Menu bar and icon

- The menu bar shows the crystal in color and pieces done over total, like `0/2`.
- Its menu shows the Main Quest's title, the next piece and pieces done, how many cards wait in the inbox, and buttons for the board, Settings and refresh.
- The app has its own crystal icon in pixel art.

### Staying fresh

- The app refreshes with a button, when the window gets focus or the menu opens, and automatically every minute.

### Settings

- The Linear API key is pasted once and stored encrypted in a local database, tied to this Mac.

## Commands

- `/quicksave-main-quest`: the same plan as the morning panel, from a Claude session. Proposes the day's Main Quest from the weekly contract and Linear, waits for an ok, and then creates it or moves the open one.

## Not built yet

- Levels and experience: the next step of making the day feel like a game.
- Sending a message to an agent and its summary, from the card.
- Hover cards for Slack messages.
- Typing your own game in the morning instead of choosing one of the five.
- A button to run the auditor's sweep from the inbox, and cards for items that came back needing you.
- A "No QA" warning in the detail when an issue does not follow the template. This one is proposed, not decided.

## Docs

- [Main Quest](docs/main-quest.md): what it is and how it lives in Linear.
- [Writing in Linear](docs/linear-writing.md): how Quicksave writes what it owns there.
- [The board](docs/board.md): what the app shows and how it stays fresh.
- [The inbox](docs/inbox.md): the deck, its decisions, undo and apply.
- [Drafts](docs/drafts.md): where the text you post yourself lands.
- [The morning](docs/morning.md): the panel that plans the day, the game and the standup.
- [Background agents](docs/background-agents.md): how the app starts agents, with their permissions.
- [Design system](docs/design-system.md): tokens and components.

## Development

- Start a Claude session on this repo with `scripts/claude.sh`, never with plain `claude`: it uses a clean profile so no outside rules, skills or memory load.
- `scripts/bundle.sh` builds the app, installs it in `/Applications` and relaunches it.
- `QUICKSAVE_SNAPSHOT=<folder>` draws every inbox card to a PNG there, without the screen, to check a change when screen capture is not available.
