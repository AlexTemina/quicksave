---
name: quicksave-main-quest
description: Propose the day's Main Quest from the weekly contract and Linear, wait for Alejandro's ok, then create it or move the open one in Linear. Use when he runs /quicksave-main-quest or asks to set the day's Main Quest.
---

# /quicksave-main-quest

Sets the day's Main Quest. It proposes, he corrects, and only then does it write. Read [Main Quest](../../../docs/main-quest.md) and [Writing in Linear](../../../docs/linear-writing.md) first: their rules apply here.

Talk to him in Spanish. Everything written to Linear is in English, with no em-dashes. Every code carries its 2-3 word tag.

## Sources

Read them at the moment of running, never from memory. A source that fails is named in the proposal, never silently dropped.

- **Linear:** the session runs on his Alan Claude account, so the Linear connector reaches the Alan workspace. Check `whoami` says "Alan EU" before trusting it; if it says anything else, stop and tell him. Writes go through `orca linear`.
  - The open Main Quest: `orca linear list-issues --team TEMI --label "Main Quest" --json`, then ignore closed ones.
  - His open work: `orca linear list-issues --assignee me --json`, with states and due dates.
  - One issue with its relations: `orca linear issue <id> --relations --json`.
- **Weekly contract:** the newest `~/vault/Journal/*Weekly Contract.md`, read only. It names the week's objectives and the milestone and date each one serves. Interim source until the contract is redesigned.
- **The day:** today's meetings from Google Calendar (`list_events`), which is his work account `alex.temina@alan.eu`. Ask for that day only, ordered by start time. Not Notion Calendar: it returns every connected calendar at once, too large to read (855k characters on 9-nov). Then ask him anyway whether anything the calendar does not show changes the plan.

## Steps

### 1. An open Main Quest comes first

- **Open and in date:** say so, show the pieces left, and stop. Nothing is created.
- **Past its due date:** it slipped. Show which pieces are left and why, as far as Linear shows it. Propose continuing with a new due date; he can also choose to close it or split it.
- **None open:** go on.

### 2. Ask about the day

Plan for the next working day, not for the calendar day it runs on. Run in the evening or on a weekend, it plans for the following working day: read that day's meetings and set the due date there. If unsure which day he means, ask first.

Show the day's meetings from the calendar and ask one question: what else changes the plan? Being away, little free time. Skip the question if he already said.

### 3. Choose the goal

1. **Candidates:** only the contract's objectives. Something else enters only if he says so.
2. **Discard:** whatever depends on another person today, unless the work is to unblock it.
3. **Yesterday failed:** propose continuing, unless it is blocked.
4. **Priority among what remains, in this order:**
   1. Due today or tomorrow, or forced by a meeting.
   2. The milestone with the least margin.
   3. The objective untouched for longest.
   4. Contract priority (P0 before P1).
5. **Fit to the day:** size the goal to the real free time from step 2.

These rules were deduced from his last days and are expected to be polished with use. When he corrects a choice, ask whether the correction is a new rule.

### 4. Check it

- One goal, one sentence. A piece about something else is a side quest and stays out.
- The whole Main Quest and each piece can plausibly be done within two days. If a piece cannot, propose the split.
- Not too small: finishing what an agent already built is not a Main Quest.
- Each piece is a real issue. Work with no issue gets one proposed.

### 5. Propose and stop

One screen, in Spanish:

- The goal, in one sentence.
- What "done" means.
- The pieces in order, each with the step it takes.
- The due date: today if it closes today, tomorrow if it closes tomorrow.
- Why this goal, in one line.
- What was discarded, one line each with the reason.
- Any source that failed.

Then stop and wait. **Nothing is written until he says ok.**

### 6. Write, after his ok

Read the open Main Quest again first. If one has appeared, stop and tell him.

**Continuing a slipped one:** only move its due date, plus any change he approved: `orca linear save-issue <id> --due-date <yyyy-mm-dd>`.

**Creating a new one:**

1. Create any split or missing issue he approved.
2. Create the issue with `orca linear save-issue`: `--team TEMI`, `--title "Main Quest: <goal>"`, `--assignee me` (the app only finds his), `--label "Main Quest"`, `--state "In Progress"`, `--due-date`, and the description with `--description "<text>"` (or `--body-file`).
3. The description holds, in this order, the "done" sentence, the numbered pieces with their links and steps, and a `## QA` section with one check: "The `## QA` of each piece passes."
4. Link each piece: `orca linear relation add <main quest> --related <piece> --type related`. Never as sub-issues.
5. If a write answers `linear_write_unconfirmed`, retry it with its `--write-id`. Never create again without it.
6. Read the issue back and confirm the label, due date and relations. Give him the link in one line.

## Never

- Write anything before his ok, or anything he did not approve.
- Post a comment, or change a piece's state, priority or labels.
- Leave two Main Quests open.
- Write in the vault.
- Keep a copy of a task's state outside Linear.
