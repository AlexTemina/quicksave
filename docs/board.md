# The board (feature 1)

What the app shows, and nothing else yet.

## What it shows

- Two kanbans, same columns (one per Linear state: Todo, In Progress, In Review, Pending for inputs, Done), same colors.
- Top: the Main Quest. A header with its title, "done" sentence, state, pieces done over total and due date; under it, its pieces as cards.
- Bottom: side quests. What goes there comes from the morning contract, designed later. Empty until then.
- Each card: the code with its 2-3 word tag, the step it takes, and its `## QA`, folded. A click opens the issue in Linear.
- Pieces show in their Main Quest order; nothing else marks the next one.
- Each card: the code, its PRs (live from GitHub: open green, CI failing red, merged purple, draft grey, closed brown), an "Agent" tag when a Claude agent is live in its Orca worktree, the tag and today's step.
- Two buttons on each card, shown on hover: open the issue in Linear, go to its worktree in Orca.
- Clicking a card opens its detail, read through the issue template: Context with the Goal, Actions (Steps) and QA as checklists, Watch out, and the rest folded under More. Common heading names (Acceptance criteria, Plan, Background…) map to the same sections.
- Empty columns collapse to a thin strip; columns with cards share the window's width.
- Everything clickable reacts on hover.

## Going to Orca

Orca owns which worktree belongs to which issue (`orca reference find <issue>`). Quicksave never guesses from names or paths.

1. A linked worktree with a live agent: bring that agent's tab forward.
2. A linked worktree without one: bring its first open terminal forward, or open a new terminal there.
3. No linked worktree: the button is off. Creating worktrees or agents is not part of the board.

## Menu bar

- The crystal in color and pieces done over total, like `0/2`. Without an open Main Quest, only the crystal.
- Its menu shows the Main Quest's title, the next piece and pieces done, with buttons for the board, Settings and refresh.

## How it stays fresh

- A refresh button.
- A refresh every time Alejandro comes back: the window gets focus, or the menu opens.
- An automatic refresh every minute, no more often.
- The board only reads Linear. The parts of the app that write are the [inbox](inbox.md) and the [morning](morning.md). The personal API key is pasted once in Settings and stored encrypted (AES-GCM, key derived from this Mac's hardware UUID) in a local SQLite database, `~/Library/Application Support/Quicksave/quicksave.sqlite`.

## Side quests and collectibles

- **Side quests** are what fits today beyond the Main Quest, never everything open. The morning plan proposes them with the free time left after meetings and the Main Quest, in the 16-oct order: breaking now, due today or overdue, any date before none and sooner first, Linear priority, then size, small first. He corrects and approves them with the plan.
- They live in the Main Quest's description in Linear, under `## Side quests`, and each one is linked to it as `related`, so Linear shows them next to it. The app tells them from pieces by that section. The board reads them from there with their live state; a closed one is crossed out. The app keeps no list of its own.
- "Add to today" lists his open issues in that same order, without the Main Quest, its pieces and collectibles, and appends the chosen one to the section and links it. Hovering a side quest shows a button to take it out of the section, which also removes the link. Both read the description fresh from Linear just before writing, so nothing written there meanwhile is lost. The issue itself never changes.
- **Collectibles** are every open issue of his with the `collectible` label (TEMI), by due date, overdue in red. The label was put on the 13 open `Read:` and `Watch:` issues on 9-nov. The auditor, which files new ones, lives in the vault and does not add it yet.
