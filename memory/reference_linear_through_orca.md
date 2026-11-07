---
name: reference-claude-account-is-alan
description: "Quicksave sessions must run on the Alan Claude account (alex.temina@alan.eu) so the Linear connector reaches Alan's workspace; calendar goes through Notion Calendar filtered to the work account"
metadata:
  node_type: memory
  type: reference
  originSessionId: 278d3528-4e65-4795-a61c-61b4756cdac9
  modified: 2026-11-06T21:49:53.796Z
---

The profile that `scripts/claude.sh` starts is separate from his normal one, and had been logged into the personal account (alextemina@gmail.com). Then the Claude Linear connector pointed at the personal workspace "Alblo Studio" and `TEMI-*` / `ES-*` came back as not found. Fixed on 6-nov-2026 with `/login` as alex.temina@alan.eu: Linear now shows "Alan EU".

If issues come back as not found, check `whoami` on the Linear connector before assuming the issue is missing.

The only exception he wants personal is GitHub: pushes go with the personal account, see [[reference-push-with-personal-account]].

Calendar: the Google Calendar connector is gone on the Alan account. Use Notion Calendar (`notion-calendar-list-events`). It holds both accounts, so always filter to `alex.temina@alan.eu` and never read the personal one.

`orca linear` also works and is still the way to write (create issue, relations, due date).
