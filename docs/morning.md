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
**Two screens.** Steps 1 to 5 are the plan. Approving moves the panel to a second screen, the standup, with steps 6 and 7. The header shows both ("1 Plan › 2 Standup") and goes back to look at the plan. The standup is optional: "Skip the standup" closes the panel, the plan is already saved, and reopening it still lets him write one.

6. **Game of the day.** While the plan is written, a job offers five games that fit the day's mood, each with its link and a one-line simile. Games already used are never offered: the job gets the whole log, and the app drops any that slips through, matching titles by their letters only, so `Papers, Please` and `papers please` are the same game. "Five more" asks for others. He also picks his score, the X/5.
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
| Plan | Linear with its comments, the weekly contract in the vault, his work Google Calendar, the Slack threads his comments link | Nothing |
| Write | Linear | The Main Quest through `orca linear`: create, relations, due date |
| Games | Only what the app passes it | Nothing |
| Standup | Slack and Linear | Nothing: returns the text |

## Open

- Typing a game of his own instead of choosing one of the five.
- The morning contract that fills Side Quests, once the weekly contract is redesigned (Tuesday 10-nov).
