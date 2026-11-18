# On-call (built 18-nov, in its first real test)

A tab for the weeks Alejandro is on the Spain Eng on-call. It reads the on-call board in Linear and the Slack calls to the on-call, proposes what to do with each card, and once he approves, writes it to Linear and starts one agent per card. It moves the `alan-spain:oncall` skill into the app; the skill keeps the procedure (triage rules, investigation, close-out), the app shows it and launches it.

## When it shows

- The tab appears only while he is on shift, or while the on-call Main Quest is open. The shift comes from Alan Home, read once a day by a small agent on Haiku. Alan Home only loads with his user settings, so that one job loads them.
- On-call cards never enter Today's board. Today shows one summary card instead (see below).

## The board it reads

- Linear: team ES, label `Eng Oncall`, without the `Technical Support` label, archived left out, and only his or unassigned: issues assigned to someone else never show, in the review, the board or the alerts (18-nov). A review card whose issue is someone else's is discarded for good as soon as the app knows it, so it never comes back as pending. Unassigned ones are proposed to be assigned to him.
- Slack: every call to the on-call handles.
  - `@spain_eng_oncall`: always counts. None of these can be missed.
  - `@eng_oncall`: counts only when the message is clearly for Spain Eng. Most of them are not.
  - A Slack call that already has its Linear issue is the same item, never two.

## Review on-call

The tab's main button. He presses it when the shift starts and any time during the day.

- A [background agent](background-agents.md) reads the board and the Slack calls and follows the skill's triage rules. It writes nothing.
- It returns a draft, one card per item:
  - the issue (or the Slack call) with its tag,
  - the proposed priority (Urgent, High, the rest) and state,
  - whether it enters his on-call board today, and one line on why or why not.
- On each card he can change the priority and whether it enters, by hand, and write a correction in a big text box, as in [Reviews](reviews.md). A conversation at the bottom takes corrections for the whole draft; the agent changes the cards in the same turn and says what changed.
- **Apply** writes to Linear (priority, state, triage) and puts the entering cards on the on-call board. It starts no agent (18-nov): he starts each one from its card.
- Pressing it again later only proposes what changed since the last review: new issues, new Slack calls, priorities someone else changed, issues closed.
- Review is disabled while the current review has a conversation and cards not applied yet: a new review replaces the current one, conversation included, and would lose what he asked (18-nov). Apply first.

## Groups (18-nov)

- Automatic alerts arrive in bursts under one parent: on 18-nov, about 25 BrowserStack accessibility findings under ES-11581 and more than 40 Sentry errors under ES-11885, many of them Urgent. Every issue has a parent problem, so the parent alone cannot tell a burst from a real topic.
- He decides it in Quicksave: a review card with a parent has "Group under <parent>". From then on, every card under that parent shows as one group card, in this review and the next ones. "Ungroup" undoes it.
- A group card shows the parent, how many cards and their priorities, and the first few titles. Its priority menu, "Enters today" switch and correction box apply to every card in it.
- A group that enters goes on the on-call board as its parent, with one agent that works the children together and looks for the cause they share. Each child's priority and state are still written one by one.
- On Telegram, a grouped parent is told once a day, however many urgent children arrive.
- The groups are his choice, kept in the app, not in Linear.

## The on-call board

- Three bands: **Urgent** (now), **High** (today), and **The rest**, folded.
- Each card shows where its work is: worktree open, agent working, draft PR (with the PR chip colors of the board), drafts ready.
- Buttons as on the board: go to the agent in Orca, open in Linear. Dragging a card to another column moves its state in Linear.

## The agents

- Start on an on-call card (never Apply) opens one parent worktree for the shift in Orca (`🚨 On-call <first day>`), and inside it one child worktree per entering card, named after the issue and linked to it. These worktrees never show on Today's board.
- Each child starts an agent with the skill's investigate-issue phase. It leaves:
  - the fix in the worktree, uncommitted;
  - a draft pull request on GitHub, created by the agent;
  - the Linear close comment and the Slack reply as [drafts](drafts.md), linked to the card. The agent writes them as files in `~/Library/Application Support/Quicksave/oncall-drafts/`; every refresh moves them into Drafts.
- Apply only writes what entered; the worktree and agent come when he presses Start on the card, so he chooses which to open.
- He goes tab by tab: checks the fix, makes it ready and sends it up himself.

## New Urgent between reviews

- Every refresh, an urgent issue on the on-call board that is not on his on-call board is told on Telegram, once.
- Every 15 minutes, an agent on Sonnet reads the Slack calls to the handles since its last look. Every new call to `@spain_eng_oncall` is told on Telegram; `@eng_oncall` only when it is for Spain Eng. The tab lists today's calls; each can be marked as read (or all at once), and read ones hide until he asks to see them. Only unread calls count as new on the tab.
- Many at once go in one message. The first look of 18-nov found 21 urgent issues and 5 calls and sent one message each.
- Nothing is applied: it waits for the next review.

## Two Main Quests

- During a shift there are two Main Quests: the on-call one and the usual one (18-nov).
- The on-call Main Quest is a real Linear issue, created on the first Apply of the shift, in TEMI, titled `On-call shift <start> to <end>`. Its description is a summary the app rewrites after every Apply ("2 urgent, 3 high, last review 11:40") and links every card that entered.
- Today shows it as a header card above the usual Main Quest; a click opens the tab. It closes as Done when the shift ends.
- The morning plan counts the shift as busy time.

## Writes

- Apply writes to Linear: priority, state and triage of on-call issues, only what he kept.
- The on-call Main Quest: created once per shift, description rewritten on every Apply, closed when the shift ends.
- Draft pull requests on GitHub, created by the card's agent.
- Never a Linear comment or a Slack message: those are drafts.

## Open

- How long the parent worktree lives after the shift ends, and what closes the child worktrees.
