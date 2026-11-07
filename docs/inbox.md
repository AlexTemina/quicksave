# The inbox (built, in its first real test)

The deck exists in the app, in its own tab next to Today, with real items from Triage and the vault's pull requests. Decisions on Triage cards are written to Linear at once, decisions on pull requests wait in the local database, and the Apply button merges or closes the pull requests and starts one agent for the items in Todo. Writes go through Orca, since Quicksave's own Linear key only reads.

Everything waiting for Alejandro's decision, in one place: a deck of cards, one at a time, made to go fast. The auditor stays in the vault. It keeps filing what needs judgment in TEMI Triage and the app only shows it.

## What it shows

- Triage items of the `Auditor` project in state `Triage`, and the open pull requests of the second brain vault.
- A triage card shows the source, what will be done (the item's "Will do") and why.
- A pull request card is laid out differently: title, what it is and a summary of what changes.
- The count of pending cards sits in the menu bar next to the Main Quest count.
- A banner says when the auditor last swept each source, and flags an old sweep or an error.
- Keyboard first, on the left hand: `D` accepts (merges a pull request), `E` accepts with a correction, `A` rejects, `Q` marks it already done, `space` leaves it for later, `⌘Z` undoes.
- Every decision is written to Linear the moment he takes it, and can be undone until he presses Apply: undoing writes the previous state back.

## The four decisions

| Decision | State written in Linear |
|---|---|
| Accept as it is | `Todo`, due the day he decides |
| Accept with a correction | `Todo`, due the day he decides, with the card's "Will do" edited by him |
| Reject, nothing to do | `Canceled`, no comment |
| Accept, already done or "I will do it myself" | `Done` |

- A correction edits the card itself: he changes its "Will do" in the deck, typed or dictated, and the app saves the edit in the item. The agent then executes the edited version. No comment is written.
- The vault's apply needs no change for any of the four: it executes `Todo`, ignores `Done`, and a `Canceled` item with no comment gets nothing.
- There is no fifth decision for items that are tasks for him (a review, telling someone, booking): the card is only the notice, he does the real task himself, so it goes to `Done` like an item already done.
- Accepting a card approves everything it names, including closing or moving to Done the issues it lists. The agent's rule of never closing an issue does not apply to what an accepted card names.
- A pull request: accept means merge, reject means close, already done means close. Proposed, not confirmed. A correction does not exist for pull requests.
- The merge or the close of a pull request happens when he presses Apply, not when he decides, because neither can be undone. Until then the decision is remembered in Quicksave's local database, since a pull request has no state in Linear.

## Undo

- Undo takes back the last decision, and again takes back the one before, in reverse order. Leaving a card for later is not a decision and is not undone.
- Triage items: undo writes the previous state back, so the item returns to `Triage`. A corrected item returns with his edited text, because the original is not kept. Whether Linear lets an item go back to `Triage` through its interface is still to be checked, in the first real test.
- Pull requests: undo only forgets the local decision.
- Once he presses Apply, nothing can be undone.

## Applying

- A button at the end of the deck ("Apply 12 decisions") starts it. The states are already in Linear by then, so Apply only starts the agent. Nothing is executed before he presses it.
- One agent, once, for everything decided. Not one per card.
- It does the same job as the vault's `/auditor apply`: it executes every approved item and moves it to `Done`. What it cannot finish goes to `Pending for inputs` with the question, and the inbox shows it as needing him.
- Its rules are the apply's rules, unchanged: it never posts comments or messages, never closes issues that are not the item itself, and leaves drafts for him.
- The vault's scheduled apply was switched off on 6-nov-2026, because two appliers would run the same item twice. Until the inbox exists, nothing executes approved items on its own. The automation was disabled, not removed, and can be turned back on.

## Starting the agent

- It runs as a job of [background agents](background-agents.md): the app starts Claude in the background, in the vault's apply worktree, with his normal Alan profile and not Quicksave's clean one: `/auditor` and everything it needs live in the vault's profile.
- It asks for the result as structured data, so the results panel and the drafts have something to read.
- Tried on 6-nov-2026 as a dry run with read-only tools: it ran as `alex.temina@alan.eu`, found no approved items and the one `Pending for inputs`, returned valid structured data and was denied nothing. It took about 30 seconds and cost about 0.76 USD, mostly reading its context, so one run per batch and never one per card.
- The dry run proved starting, account and result format. It did not prove writing: the real apply also writes Linear, commits to the vault and merges, and what it is allowed to do unattended is still the open permission question.

## Results, drafts and the report (proposed)

The apply writes a report and leaves drafts of anything that would post text somewhere. In the app:

- The agent hands back a structured result: one row per item with what happened and its links, and a list of drafts, each with where it goes, its link and its text.
- After the button, a results panel shows the report as rows: done, needs you, failed.
- The drafts do not stay in this panel: they go to the [Drafts](drafts.md) section, and the panel says how many were added.
- Nothing goes to Telegram when the run starts from the app, because he is looking at it.
- What needs him comes back to the deck as a card with its question and a box to answer.

## Writing

This is the only part of the app that writes to Linear: states, due dates and the edited "Will do" of a card, each one at the moment he decides the card. Pull requests are the exception: they are only written, by merging or closing, when he presses Apply. The app never writes a comment. The board still only reads.

## The Main Quest gate

`/quicksave-main-quest` does not propose while the inbox has pending cards, because the day would be planned on a stale picture. It lists what is pending and waits.

## Open

- The results panel and the drafts, as proposed above.
- The agent's permission mode when the app starts it. Proposed: no prompt for each action, the apply's rules as the only limit.
- Pull request decisions, as proposed above.
