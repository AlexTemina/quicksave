# The One

The One is the minimum Alejandro must get done for the day to be a good day. Code or not, it does not matter.

## What it is

- One big thing per day, said in one sentence: "Mo plugged in from Spain".
- It is sized backwards: the day serves the week, the week serves the next checkpoint, the checkpoints serve the quarter.
- Too small is a failure too. Finishing what an agent already built is not a The One.
- When it takes several tasks, they are done in order, one after another, never in parallel.

## How it lives in Linear

- The One is a Linear issue in TEMI, with the label `The One` and the day as its due date. That is how the app finds today's.
- Its pieces are the real issues (TEMI or Alan teams), linked with a `related` relation. Never as sub-issues: a piece usually has its own parent already.
- The description says what "done" means in one sentence and lists the pieces in the order they are done, each one linked.
- Its QA is the sum of its pieces' `## QA`. The app reads them from the pieces; nothing is copied into The One, because a copy goes stale.
- State lives only in Linear. The One is done when every piece is closed and its QA passes.

## Over time

- Not finished today: the same issue carries on tomorrow, with its due date moved. That way it shows how many days it took.
- Finished: the next The One for the same day is worked out then.

## Open

- How `/quicksave-morning` picks the pieces, and what it asks Alejandro before creating the issue.
