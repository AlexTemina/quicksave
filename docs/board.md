# The board (feature 1)

What the app shows, and nothing else yet.

## What it shows

- Two kanbans, same columns (one per Linear state: Todo, In Progress, In Review, Pending for inputs, Done), same colors.
- Top: the Main Quest. A header with its title, "done" sentence, state, pieces done over total and due date; under it, its pieces as cards.
- Bottom: side quests. What goes there comes from the morning contract, designed later. Empty until then.
- Each card: the code with its 2-3 word tag, the step it takes, and its `## QA`, folded. A click opens the issue in Linear.
- The next open piece has a light accent background.
- Two buttons on each card: open the issue in Linear, and go to its worktree in Orca.

## Going to Orca

Orca owns which worktree belongs to which issue (`orca reference find <issue>`). Quicksave never guesses from names or paths.

1. A linked worktree with a live agent: bring that agent's tab forward.
2. A linked worktree without one: bring its first open terminal forward, or open a new terminal there.
3. No linked worktree: the button is off. Creating worktrees or agents is not part of the board.
- Menu bar: the Main Quest's title and pieces done over total, like `0/2`.

## How it stays fresh

- A refresh button.
- A refresh every time Alejandro comes back: the window gets focus, or the menu opens.
- An automatic refresh every minute, no more often.
- It only reads Linear, never writes. The personal API key is pasted once in Settings and stored encrypted (AES-GCM, key derived from this Mac's hardware UUID) in a local SQLite database, `~/Library/Application Support/Quicksave/quicksave.sqlite`.
