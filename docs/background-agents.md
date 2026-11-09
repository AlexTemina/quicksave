# Background agents (designed, not built)

Quicksave starts agents in the background for jobs it cannot do itself. One piece of the app does it, whatever the job: applying the [inbox](inbox.md) first, others later.

## Two kinds of agent

- **Jobs:** unattended, one result, structured. The app starts them with Claude Code in print mode. This document is about them.
- **Work agents:** the ones that code in Orca worktrees, which he watches and steers. They stay in Orca and the board only shows their state.

## What a job declares

- What it is for, and the prompt.
- Where it runs and with which profile: his normal Alan profile when it needs the vault's commands, Quicksave's clean profile otherwise.
- The result it must return, as a schema.
- What it may do: a list of allowed actions and a list of denied ones.
- The model, the effort and a limit of turns.

## How the app runs it

- One background process per job. Jobs queue and run one at a time per folder, because two runs in the same worktree would collide.
- States: queued, running, done, needs you, failed. What is running, since when, and a cancel button are always visible.
- The result is read as data. A result that cannot be read counts as failed and shows the raw text.
- Every run is kept in the local database: job, start, duration, cost, outcome and what was denied.
- A result that needs him goes back to the inbox as a card. Drafts go to [Drafts](drafts.md).

## Permissions (decided 6-nov-2026: a list, never skip)

- Never skip permissions. Claude Code itself recommends that only for sandboxes with no internet, and these jobs read Slack, GitHub and mail content through the items the auditor files. With everything allowed, "never post" is a promise in the prompt. With a list, it is a wall.
- Mode `dontAsk` with an explicit list of allowed actions: whatever is not listed is denied without stopping to ask. To be confirmed with a test.
- A denied list for what he never wants unattended, whatever the allowed list says: posting to Slack, sending mail, commenting on GitHub, force pushes.
- Each job type has its own lists. They start tight and are widened from the denials seen in real runs, which every result reports.

## Model

- Chosen per job.
- The same read-only dry run of the apply, on 6-nov-2026:

| | Opus 5.5 | Sonnet 5.5 |
|---|---|---|
| Cost | 0.76 USD | 0.32 USD |
| Time | 33 s | 17 s |
| Turns | 9 | 7 |
| Result | no approved items, `TEMI-80` pending | the same |

- The apply starts on Sonnet 5.5. The dry run had nothing to execute, so it does not show how each model handles writing: the first real runs are watched, and a job can go back to Opus if Sonnet gets it wrong.

## What the apply has done (history, 11-sep to 6-nov-2026)

Of 447 items of the Auditor project, 355 ended in Done, 60 in Canceled, 2 in Duplicate and 29 are in Triage. Grouped by what the closed ones asked:

| Family | Items | What it needs |
|---|---|---|
| Edit Linear issues (record, note, dates, links, moves) | 115 | Linear writes: fields, descriptions, relations, states |
| Draft text for him to post | 70 | Nothing: the text goes out as a draft |
| Create issues | 69 | Linear: create issue |
| Merge vault pull requests | 53 | Merge, in the vault repository only |
| Orca worktree board (mark completed, flag) | 23 | Orca worktree metadata |
| Other | 87 | Mixed, see Open |

## The apply's lists (proposed from that history, to be tested)

Allowed:
- Read, search and list files in the vault, and edit its content.
- Linear through `orca linear`: list, read, create and update issues, relations, states, due dates, labels, priority, assignee, estimate.
- Orca worktrees: list, show and `set` (metadata).
- GitHub: view, list and merge pull requests of the vault repository.
- Git in the vault: status, diff, log, fetch, add, commit and push to `main`.

Always denied:
- Any Linear comment, any Slack, mail or GitHub post, review or comment.
- Force pushes, hard resets, deleting files in bulk, removing worktrees.
- Merging pull requests of any repository other than the vault.

Whether a list entry can be limited to one repository is to be confirmed with a test.

## The morning's jobs

Plan, write, games and standup, each with its own lists. See [the morning](morning.md).

## Open

- The "Other" family: about 87 items, a good part of them tasks for him and the auditor's own failure alerts. Settled in the [inbox](inbox.md): the card is a notice and goes to Done, and accepting a card approves what it names, closing issues included.
- A spending limit per run, if Claude Code offers one.
