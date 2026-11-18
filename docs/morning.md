# The morning

The morning is a panel, not a tab: it is done once a day and then left. It plans the day's Main Quest with Alejandro, lets him choose the game of the day and leaves the standup in [Drafts](drafts.md). It replaces running `/quicksave-main-quest` by hand and the vault's `/morning` and `/standup`.

## Where it starts

- **The board:** with no open Main Quest, a big "Start the day" button sits where the Main Quest goes. With one open, a small button in the header lets him plan the day again.
- **The menu bar:** a "Start the day" line opens the window with the panel.
- Closing the panel loses nothing: what he wrote, the plan and the games stay until he presses "Start over", or until the next day.

## Steps

1. **Never during Apply.** While the inbox's Apply runs, the agents are changing Linear, and a plan would read it half done. The panel only says that Apply is running and what it is doing: proposing, correcting and approving stay off until it finishes, with no way around it.
2. **Inbox first.** When the [inbox](inbox.md) has cards to decide, or accepted items waiting for Apply, the panel says so at the top with a button to the deck. The plan reads Linear, and what sits in the inbox is not in it yet, so proposing stays off until the inbox is clear. "Continue anyway" lifts that for the day.
3. **His comments.** A box for what the calendar does not know: being away, little free time, what he wants to push.
4. **Propose.** A background job proposes the Main Quest and the side quests that fit the day. It follows steps 1 to 5 of [`/quicksave-main-quest`](../.claude/skills/quicksave-main-quest/SKILL.md): it reads Linear, the weekly contract and his work calendar, and returns the plan. The panel shows the goal, what "done" means, the pieces in order with their step, the due date, why this goal, what was left out, today's meetings and any source that failed. It writes nothing.
5. **Correct or approve.** A correction sends the plan back to the job with every earlier correction, as many times as he wants. Approving writes it to Linear (step 6 of the skill): it creates the Main Quest, or moves the due date of a slipped one, and writes the side quests into its description. When the open Main Quest is in date and there are no side quests, there is nothing to write. A write that fails can be retried.
   - **An open Main Quest is a fact, not a guess.** The app tells the plan which Main Quest is open in Linear. When the plan creates a new one while another is open, the panel says so and he picks how the old one ends: "Close it as Done" or "Cancel it". Approve stays off until he picks. "Continue it instead" asks the plan to keep the old one with a new date. On approval the app closes the old one first, then the new one is written (16-nov: the plan assumed TEMI-577 was closed, the write refused, and nothing reached Linear).
**Two screens.** Steps 1 to 5 are the plan. Once the plan is in Linear, the panel moves to a second screen, the standup, with steps 6 and 7. The header shows both ("1 Plan › 2 Standup") and goes back to look at the plan. If the write fails or needs him, the panel stays on the plan with the warning and "Try again": the standup never starts on a plan that did not land. The standup is optional: "Skip the standup" closes the panel, the plan is already saved, and reopening it still lets him write one.

6. **Game of the day.** While the plan is written, a job offers five games that fit the day's mood, each with its link and a one-line simile. Games already used are never offered: the job gets the whole log, and the app drops any that slips through, matching titles by their letters only, so `Papers, Please` and `papers please` are the same game. "Five more" asks for others. He can also type a game of his own (`san andreas`): a job finds the full title, its link and a simile for today, and it appears first, already chosen. An ambiguous name brings up to three to pick from. A game he types is allowed even if already played: its card says when. He also picks his score, the X/5.
7. **Standup.** A job writes the standup in his usual form, with the chosen game in the `:firecracker:` line and the Main Quest as `:target:`. It reads his last standups and his Linear to get the facts right, and finds today's "Spain Area Standup" thread. The text lands in Drafts, linked to that thread, where "Draft in Slack" leaves it in his Slack without sending. The game goes into the log at that moment.

## The game log

- Every game used in a standup, with the date, the score, the simile and a link. The panel shows it under "Played before".
- It lives in the local database. The vault's `Personal/Standup Game Similes.md` was imported once, the first time the panel opened, and is no longer used.

## Writes

- Approving the plan is the second part of the app that writes to Linear, after the inbox. Only what the plan says: the Main Quest, its relations, its due date and any new piece he approved. Never a comment, never a piece's state, priority or labels.
- The standup is never posted or left in Slack by the job: it goes to Drafts, and he sends it himself.

## Jobs

Each one is a [background agent](background-agents.md) with its own list of allowed actions, on Sonnet 5.5.

| Job | Reads | Writes |
|---|---|---|
| Plan | Linear with its comments, the weekly contract (a TEMI issue), his work Google Calendar, the Slack threads his comments link | Nothing |
| Write | Linear | The Main Quest through `orca linear`: create, relations, due date |
| Games | Only what the app passes it | Nothing |
| Typed game | Only what he typed and the day | Nothing |
| Standup | Slack and Linear | Nothing: returns the text |

## Open

- The morning contract that fills Side Quests, once the weekly contract is redesigned (Tuesday 10-nov).

## Auditor

- The plan screen opens with one card, in plain words: when the auditor last read his sources (Slack, mail, GitHub, Linear, meetings), or that it is reading them now. A source it could not read is named, with when it was last read and the error, because the Inbox may be missing things from there.
- It is read from the auditor's watermark on the vault's `main` and from Orca's runs of the `auditor-deep` automation. Quicksave never writes either.
- **Read again now** asks Orca to run `auditor-deep` at once. It is hidden while a run is going, so two never overlap in the same worktree.
- **What it said** opens, in a popover, what the last run said when it ended (the sources it read and what it changed), as Orca kept it, with the run number and when it ended. Hidden while a run is going.
- The morning never waits for it: a run took 50 minutes on 10-nov. When a run the panel saw going ends, the inbox is read again, and what it filed shows in the gate.
- The first version listed every source as a chip with two different times, and he could not read it (10-nov).

## What the plan must look at

The app reads Linear itself and hands the plan four lists, so the agent cannot leave something out unnoticed:

1. **The window:** every open issue of his that is overdue or due by the end of Alan's week (the coming Wednesday, today included), urgent or high, or in progress, in review or pending for inputs. Collectibles, the Main Quest and cards of kind Read or Track aside (18-nov). Each one must end up as a piece, a side quest, or left out with its reason. If the plan forgets one, the panel says which.
2. **Always in, whether the day fits it or not:** every issue of his due today or overdue (16-nov), and every one In Progress, In Review or Pending for inputs (18-nov), is a side quest. Only the Main Quest's pieces stay pieces. The plan is asked to do it, and the app adds any it left out before showing the plan.
3. **Someone waits:** after what breaks and what is due, the plan ranks cards of kind Answer, Unblock and Review, because a person is blocked until he acts, before his own work with a later date (18-nov). See the kinds in [the board](board.md).
4. **The medium slot:** one side quest a day comes from his medium, low or no-priority issues in Todo outside the window, the one untouched for longest first, so the middle of the pile moves too. It shows as "(medium slot)".
4. **His projects:** the projects he leads (not the Auditor's), their open issues not assigned to him in the same window. The plan lists under "Your projects: worth a look" only what needs his eye today: overdue, blocked, waiting on him, risky for a date.

The weekly review of the whole pile, so medium things get a date they deserve, happens in the Tuesday contract session (12-nov): every open issue leaves with a date, Backlog or canceled.
