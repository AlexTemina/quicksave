# Main Quest

The Main Quest is the minimum Alejandro must get done for the day to be a good day. Code or not, it does not matter.

## What it is

- One goal, said in one sentence: "Teleconsultation flag in main". Every piece serves that same result. A piece about something else does not enter: it is a side quest.
- Sized to one or two days. Bigger than that is a milestone, and the Main Quest is the one- or two-day slice that moves it forward.
- It is sized backwards: the day serves the week, the week serves the next checkpoint, the checkpoints serve the quarter.
- Too small is a failure too. Finishing what an agent already built is not a Main Quest.
- When it takes several pieces, they are done in order, one after another, never in parallel.

## Size check

- Every piece is checked when it enters: can it plausibly be done within two days?
- If not, it is split before it enters. Alejandro approves the split; the slice that fits becomes the piece, the rest stays as its own issue.
- The Main Quest as a whole passes the same check.

## How it lives in Linear

- A Linear issue in TEMI with the label `Main Quest`. Only one is open at a time: that is how the app finds it.
- The due date is when it should end, decided when it is created: today if it closes today, tomorrow if it is planned to start today and close tomorrow.
- Past its due date means it slipped. That is the signal, not carrying over.
- Its pieces are the real issues (TEMI or Alan teams), linked with a `related` relation. Never as sub-issues: a piece usually has its own parent already.
- The description says what "done" means in one sentence and lists the pieces in order, each one linked, with the step it takes.
- Today's side quests go in its description too, under `## Side quests`, one line each: `- [ES-123 (title)](url): why`. Only what fits the day. They are linked as `related` too, so Linear shows them next to the Main Quest. That is the one exception to "related means piece": a related issue listed under `## Side quests` is a side quest, every other related issue is a piece.
- Its QA is the sum of its pieces' `## QA`. The app reads them from the pieces; nothing is copied into the Main Quest, because a copy goes stale.
- State lives only in Linear. The Main Quest is done when every piece is closed and its QA passes. Then the next one is created.

## How the goal is chosen

The [morning](morning.md) panel proposes and Alejandro corrects, through the same rules as `/quicksave-main-quest`, which still works from a Claude session. Nothing is written in Linear before his ok.

An open Main Quest comes first: in date, nothing is created; past its due date, it proposes continuing with a new date, and he can close or split it instead.

These rules were deduced from his days from 20-oct to 5-nov and are polished with use:

1. Candidates: only the weekly contract's objectives, unless he says otherwise.
2. Discard what depends on another person today, unless the work is to unblock it.
3. If yesterday failed, propose continuing, unless it is blocked.
4. Among what remains: due today or tomorrow or forced by a meeting, then the milestone with the least margin, then the objective untouched for longest, then contract priority.
5. Fit the goal to the day's real free time, which he is asked about.

## Open

- The weekly contract lives in Linear since 12-nov: the open TEMI issue with the label `Weekly Contract`. Its objectives are the candidates of rule 1. The skill and the morning job still read the vault file until the code follows.

