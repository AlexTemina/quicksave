---
name: reference-claude-account-is-alan
description: "Quicksave sessions must run on the Alan Claude account (alex.temina@alan.eu) so the Linear connector reaches Alan's workspace; calendar goes through the Google Calendar connector, which is the work account"
metadata:
  node_type: memory
  type: reference
  originSessionId: 278d3528-4e65-4795-a61c-61b4756cdac9
  modified: 2026-11-06T21:49:53.796Z
---

The profile that `scripts/claude.sh` starts is separate from his normal one, and had been logged into the personal account (alextemina@gmail.com). Then the Claude Linear connector pointed at the personal workspace "Alblo Studio" and `TEMI-*` / `ES-*` came back as not found. Fixed on 6-nov-2026 with `/login` as alex.temina@alan.eu: Linear now shows "Alan EU".

If issues come back as not found, check `whoami` on the Linear connector before assuming the issue is missing.

The only exception he wants personal is GitHub: pushes go with the personal account, see [[reference-push-with-personal-account]].

Calendar: the Google Calendar connector is back and is the work account (checked 9-nov-2026). Use its `list_events` for one day, ordered by start time. Do not use Notion Calendar for this: it returns every connected calendar at once, personal included, and today's answer was 855k characters, too large to read.

`orca linear` also works and is still the way to write (create issue, relations, due date).
