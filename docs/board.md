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
- Dragging a card to another column moves its issue to that state in Linear, in either board. The card shows in its new column at once, faded, until Linear confirms and the board refreshes; if Linear refuses, a note says why and the card goes back.
- Empty columns show only their dot and name, sideways. When a board has an empty column, columns with cards stop growing at a set width and the empty ones take the rest, so every state keeps its place and Done stays on the right. Three done pieces filling three quarters of the row did not look done (9-nov).
- Everything clickable reacts on hover.

## Going to Orca

Orca owns which worktree belongs to which issue (`orca reference find <issue>`). The one name Quicksave reads is the agent tab's title, which `/start-task` sets to the issue's code (`ES-12867 — …`).

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
- The board reads Linear and writes only one thing: an issue's state, when he drags its card to another column. The other parts of the app that write are the [inbox](inbox.md) and the [morning](morning.md). The personal API key is pasted once in Settings and stored encrypted (AES-GCM, key derived from this Mac's hardware UUID) in a local SQLite database, `~/Library/Application Support/Quicksave/quicksave.sqlite`.

## Side quests and collectibles

- **Side quests** are what fits today beyond the Main Quest, never everything open. The morning plan proposes them with the free time left after meetings and the Main Quest, in the 16-oct order: breaking now, due today or overdue, any date before none and sooner first, Linear priority, then size, small first. He corrects and approves them with the plan.
- They live in the Main Quest's description in Linear, under `## Side quests`, and each one is linked to it as `related`, so Linear shows them next to it. The app tells them from pieces by that section. The board reads them from there with their live state; a closed one is crossed out. The app keeps no list of its own.
- "Add to today" lists his open issues in that same order, without the Main Quest, its pieces and collectibles, and appends the chosen one to the section and links it. Hovering a side quest shows a button to take it out of the section, which also removes the link. Both read the description fresh from Linear just before writing, so nothing written there meanwhile is lost. The issue itself never changes.
- **Collectibles** are every open issue of his with the `collectible` label (TEMI), by due date, overdue in red. The label was put on the 13 open `Read:` and `Watch:` issues on 9-nov. The auditor, which files new ones, lives in the vault and does not add it yet.

## End the day

- **End the day**, in Today's header next to Start the day, opens an agent in the vault, in Orca, that runs `/evening`: what happened, what the day was worth, and what it keeps. He follows it and answers it there. There is no scheduled evening any more (11-nov).

## Tuesday

- Tuesday closes Alan's week, and these are due every Tuesday: the Linear weekly status updates of his projects and the crew initiative, before 14:00 (the Spain area weekly flow reads them then), and the weekly SFA in the afternoon.
- On Tuesdays Today opens with a card with three steps, each with **Draft it**, which starts an agent in the vault with his normal profile. It only reads and returns drafts, which land in Drafts; he reviews and posts them. The card then says how many drafts are ready.
- **Draft it** opens a box under the step for what he wants in it, as "Start the day" opens his comments before the plan; the agent starts from the box's own **Draft it**, and **Cancel** closes it. He writes there what the calendar and Linear do not know: a project at risk, the headline of the week, his suns and fires. The agent builds the draft around it and uses what it reads to complete it; where they disagree, it keeps his version and says so. What he wrote stays until the next Tuesday, and shows as text while the agent drafts (11-nov).
  1. **Project updates**: the vault's `/crew-weekly dry-run`, one draft per project.
  2. **Initiative update**: the vault's `/initiative-weekly dry-run`. It comes second because it rolls up the project updates, so it stays off until the project drafts exist. It reads the posted project updates, and for any not posted yet it uses the draft as it reads in Quicksave, and says so.
  3. **Weekly SFA**: `/write-sfa` without archiving.
  4. **Previously, on my SFA**: once the SFA is posted, the reply in its thread that says how the A+ of his previous SFA went, one line each with :white_check_mark:, :large_yellow_circle: or :red_circle:. Until the SFA is posted the step waits. Its draft points at the SFA's message, so "Draft in Slack" leaves it in that thread (11-nov).
- **Done means posted, never an archived draft.** On 11-nov he archived the SFA draft without posting it and the card went away. Now:
  - Project updates: every project he leads, planned or under way and under an initiative, has a status update in Linear since Tuesday. The step names any still missing. His own TEMI projects never count.
  - Initiative update: one by him in Linear since Tuesday.
  - SFA: his message in #org_alaner-sfa since Tuesday; Previously: his reply in that message's thread. Both are looked for by a small agent on Haiku, at most every 30 minutes and only while one is missing.
  - **Posted**, on each step, ticks it by hand for the week when the app does not see it.
- On Tuesday the card shows the three steps, posted ones ticked. From Wednesday to Monday it stays, titled "Left from Tuesday", with only what is still not posted, and goes away when everything is. The morning plan counts half an hour for a missing SFA.
- The morning plan counts about an hour for each as busy time on Tuesdays.

## Open, not planned

- Everything open in Orca that belongs to an issue not on the board (not the Main Quest, one of its pieces or a side quest of today) shows on the side quests' board, so nothing open escapes Quicksave:
  - every open worktree, except main checkouts and the vault's fixed automation worktrees (🚫);
  - every live agent whose conversation is named after an issue ("ES-12986 — …"), wherever it runs, as in the vault's or alan-apps' main checkout (12-nov).
- A worktree's issue comes from its Linear link in Orca, else the code its name or branch starts with (ES-12279-…, alextemina/temi-480-…), else its parent worktree's, else the code its live agent's conversation starts with.
- Agents no issue names (a conversation in the vault's main checkout, say) are not on the board.
- They sit in the column of their issue's Linear state, with a dashed edge, a lighter fill and the tag "Open, not planned". They show the repo and worktree, and the last progress its agent left in Orca. They do not count in the day's progress.
- One whose issue is done says "Done, worktree still open", or "Done, agent still open" when only an agent holds it: it can be closed.
- The + on the card adds it to today as a side quest. Dragging it moves its issue's state, like any card.
- Everything open that no issue names sits apart below the side quests, under "Open with no issue", as small dashed cards (12-nov):
  - every live agent with no issue, wherever it runs: its name, where (vault main, a worktree), its last words, and painted like any agent's card (yellow working, orange its turn, purple blinking when it asks);
  - every worktree with no issue and no agent, tagged "No agent": it can probably be closed.
  - They use the same card as the board's, with a dashed edge (12-nov): the buttons float over the corner on hover, and hovering shows the agent's last reply.
  - Clicking an agent opens its detail, like a piece's: its state, when it last moved, where it runs, and its last reply in full. Clicking a worktree with no agent goes to it in Orca.
  - Naming an agent after its issue ("ES-123 — …") moves it to the board. The vault's fixed automation worktrees (🚫) stay out.

## The week's contract

- At the top of Today, a card with the week's contract: its dates, how many days are left ("Last day", or "Over: a new contract is due"), and one tile per objective with its priority (P0 red, P1 orange, P2 grey), its text, the issues it names with their live state from Linear (done ones crossed out), a bar of done over total and what it serves. An objective whose issues are all done turns gold.
- Read from Linear (12-nov): the open TEMI issue with the label `Weekly Contract`, every refresh. Objectives are the numbered items under `## Objectives`, each with its priority and its issues; "Carried over" folds `## Carried over`. A button opens the issue in Linear.
- Until the code follows, the card still reads the newest `~/vault/Journal/*Weekly Contract.md`, whose last one is 4-nov.
- How the contract is made: the vault's `Claude/templates/weekly-contract.md` and `/weekly-contract`, on Tuesday afternoon after the Spain area weekly. Building it from the app is still to design.

## Layout and progress

- The board is three things: the Main Quest's board, the side quests' board below it, and the collectibles in a column down the right side, next to both. Under 1180 points of window width the collectibles move below the side quests, so nothing runs off the window.
- A row of columns takes the height of its tallest column measured at its real width; columns never cut their cards.
- Side quests are pieces in every way but their place: the same board (one column per Linear state, empty ones shrunk to a strip), the same card (code, due date, pull requests with live CI, the Agent tag, the Linear and Orca buttons, the Actions bar) and the same detail on click. A side quest's card adds a button to take it out of today.
- With several pull requests, a card shows one tag ("5 PRs") in the color of the one that needs him most: failing CI, then open, draft, merged, closed. Hovering it lists them with their titles, each one clickable. The detail still shows them all.
- On a card, code, due date and badges wrap to a new line when the column is narrow, and the buttons float over the corner on hover, so nothing is squeezed.
- Quicksave should feel like a game, so finishing things should feel good. Progress bars come first; levels and experience come later.
  - **Day:** one bar at the top with every piece (gold) and every side quest (green), and "Day cleared" when all are done.
  - **Main Quest** and **side quests:** a bar each, one segment per issue.
  - **Each piece:** a small bar with the Actions ticked in its issue.
  - A done segment fills with a glossy gradient and pops up, the bar bounces when it moves, and a full bar glows.

## Agent status

- Every card is painted with what its issue's agent is doing, to see it at a glance, from `orca worktree ps`, read every 8 seconds: **yellow** working (the card breathes, about once a second, from almost clear to strong yellow), **orange** its turn ended (or it only watches a background task it left running, which Orca calls "monitoring"; it was green until 9-nov, which looked like done), **purple and blinking fast** stopped on a question or a permission prompt, with the tag "Asks you": it cannot go on until he answers (11-nov), **grey** idle, **red** error. A card with no agent keeps its normal look.
- An issue's agent is one in the worktree linked to it, or any agent whose conversation is named after it (`ES-12867 — …`). With several, the one that needs him most wins, then the most recent.
- Only agents with an open terminal count: Orca keeps the record of agents closed long ago, and one of them painted `ES-12726` green on 9-nov. The card's Orca button goes to the same agent its color comes from.
- The color fills the card; the border stays the normal hairline.
- **New reply** (12-nov): an orange card whose reply he has not looked at from Quicksave carries a bell, "New reply", and the strong orange. Once he has seen it, the orange fades and the bell goes, so a seen card he has not acted on reads apart from a new one. Only a click in Quicksave counts as seen: the card, its detail (a reply that arrives while it is open counts too) or its Orca button. Looking in Orca does not, by his choice, so the app stays in control. When the agent works and ends a new turn, the bell comes back. The same goes for the cards under "Open with no issue".
- Hovering the card shows the agent's last reply. The piece's detail shows it in full, with when it last moved.
- **Close the agent** (12-nov): every card with a live agent, on the board or under "Open with no issue", has a button on hover, and in its detail, that closes the agent's tab in Orca and ends its session. The worktree, its files, its other terminals and Linear do not change. A working (yellow) agent asks first, since what it is doing is lost; one that waits or is idle closes at once. Closing a worktree is not in the app.
- Commands run by the app are read while they run: `orca worktree ps` prints more than a pipe holds, and read only at the end it never finished (9-nov).

## Watching what waits

A card in **Pending for inputs** or **In Review** waits for someone else. The app looks for the answer so he does not have to (11-nov).

- **Every 10 minutes, with no Claude and no tokens:** new comments on the issue in Linear; reviews, comments, CI turning green or red, merged, closed or conflicts on its pull requests; answers in the GitHub discussions it links. His own comments and integrations (`linear-code`, `alan-pr-check`, bots) never count.
- **Every 30 minutes, Slack:** the threads the issue links (in its description, comments or attachments) are read by a small agent on Haiku that only reads. It only runs when a waiting card links a thread, so it costs nothing on most checks.
- **The first look only marks where it starts.** What was already there when the card entered the column is not news. A card that leaves the column is forgotten, and starts again if it comes back.
- **What is new wakes its agent:** the app types one line into the agent's tab in Orca with what it found, and asks it to carry on and leave any answer as a draft. It never types into an agent stopped on a permission prompt, where a key could answer it.
- **A red CI in review gets fixed.** When the CI of a card in In Review is red (already red at the first look, or turning red later), its agent is asked to find why and fix it. He authorised it, on 11-nov, to commit and push the CI fix to that pull request's branch, and nothing else: no force push, no merge, no comments. If the failure is not the pull request's (flaky test, main broken), it pushes nothing and says why. At most three tries per pull request.
- **He hears how it went, on Telegram,** through the vault's notify script: when the fixing agent stops, its last reply (how it fixed it, or why not). With no agent to ask, an agent stopped on a prompt, or three tries spent, a message says the CI is red and was not fixed.
- CI turning green shows on the card but wakes no one: it is not worth an agent's turn.
- **Each source keeps its own mark,** moved only when it was read. A source that fails (GitHub or Linear down, Slack's agent failing) is read again from the same point on the next look, so nothing that arrived meanwhile is lost. Until 11-nov one failed read moved the mark anyway and could drop a review for good.
- **It only runs while the app is open.** With the app closed or the Mac asleep nothing is looked at, but the marks stay: the first look after reopening (30 seconds in) catches up on everything since.
- **The card shows it:** a "News" tag with what was found and whether the agent was woken, until he marks it seen. Without news it says when it last looked at that card and how many places it read ("nothing new 3 min ago · 3 sources"); if a source failed, it says which in orange, and that it retries in 10 minutes.
- Nothing is written to Linear, GitHub or Slack.
