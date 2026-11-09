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

Orca owns which worktree belongs to which issue (`orca reference find <issue>`). The one name Quicksave reads is the agent tab's title, which `/start-task` sets to the issue's code (`ES-12867 — …`), as Save Point did.

1. A linked worktree with a live agent: bring that agent's tab forward.
2. A linked worktree without one: bring its first open terminal forward, or open a new terminal there.
3. No linked worktree, but an agent tab titled with the issue's code, wherever it runs: bring it forward.
4. Nothing: the button becomes **Start**. `/start-task` runs in the background from the vault and opens the alan-apps worktree and the agent tab in Orca, which comes forward. When the work needs no worktree (admin, writing, a decision), Quicksave opens the agent itself, in Orca, in the vault, in auto mode, with the tab and the session named `<code> — <tag>` and `/start-task`'s kickoff rules. Either way the next click finds that tab by rule 3.

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

## Layout and progress

- The board is three things: the Main Quest's board, the side quests' board below it, and the collectibles in a column down the right side, next to both.
- Side quests are pieces in every way but their place: the same board (one column per Linear state, empty ones shrunk to a strip), the same card (code, due date, pull requests with live CI, the Agent tag, the Linear and Orca buttons, the Actions bar) and the same detail on click. A side quest's card adds a button to take it out of today.
- On a card, code, due date and badges wrap to a new line when the column is narrow, and the buttons float over the corner on hover, so nothing is squeezed.
- Quicksave should feel like a game, so finishing things should feel good. Progress bars come first; levels and experience come later.
  - **Day:** one bar at the top with every piece (gold) and every side quest (green), and "Day cleared" when all are done.
  - **Main Quest** and **side quests:** a bar each, one segment per issue.
  - **Each piece:** a small bar with the Actions ticked in its issue.
  - A done segment fills with a glossy gradient and pops up, the bar bounces when it moves, and a full bar glows.

## Agent status

- Every card is painted with what its issue's agent is doing, to see it at a glance, from `orca worktree ps`, read every 8 seconds: **yellow** working (the color breathes), **green** waiting for him (its turn ended, or it needs a permission or an answer), **grey** idle, **red** error. A card with no agent keeps its normal look.
- An issue's agent is one in the worktree linked to it, or any agent whose conversation is named after it (`ES-12867 — …`). With several, the one that needs him most wins, then the most recent.
- Only agents with an open terminal count: Orca keeps the record of agents closed long ago, and one of them painted `ES-12726` green on 9-nov. The card's Orca button goes to the same agent its color comes from.
- The color fills the card; the border stays the normal hairline.
- Hovering the card shows the agent's last reply. The piece's detail shows it in full, with when it last moved.
- Commands run by the app are read while they run: `orca worktree ps` prints more than a pipe holds, and read only at the end it never finished (9-nov).
