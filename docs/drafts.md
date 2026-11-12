# Drafts (built)

A tab next to Today and Inbox, with the open drafts and an archive view. Select the drafts already posted and archive them, or restore them from the archive. The agent that applies the inbox adds its drafts here.

One section of the app where every draft lands, whichever part of the app produced it. Quicksave never publishes: a draft is text Alejandro posts himself, somewhere else.

## Where drafts come from

- The agent that applies the [inbox](inbox.md): anything that would post text (a Linear comment, a Slack message, a GitHub comment, a mail) becomes a draft instead.
- Any other part of the app that proposes text to send, now or later.

## What a draft is

- The text, ready to paste.
- Where it goes (Linear, Slack, GitHub, mail) and a link straight to that place.
- Where it came from: the inbox item or the feature that produced it, with its link.
- When it was made.
- Its state: open or archived.

## What he does with it

- Copy the text, and open the place it goes to. Quicksave never posts it.
- Select the ones already posted, one or many, and archive them.
- Archived drafts leave the list but are kept, in an archive view, so a draft can come back.
- Drafts are Quicksave's own data and not a task's state, so they live in the local database and survive closing the window.

## Talking about a draft (10-nov)

Each draft has a "Talk" button that opens a conversation with the agent under the text.

- It is the shared AI conversation (see the design system): what the agent may touch on top, the conversation, what it is doing right now while it works, and a box where Return sends and Shift-Return adds a line (11-nov).
- He writes what to change, or uses a quick button: Shorter, Less jargon, More direct.
- When the draft keeps the session of the agent that wrote it (Tuesday's rituals), that same session continues, so it remembers everything it read and answers in seconds. Each turn forks the session, so the original is never touched and two drafts of the same batch can be talked over at once.
- A draft without a session (older ones, the inbox's) starts a new agent with the conversation so far, which may read the item behind it. From its first answer on, that session continues.
- The agent answers with a new version, shown as it will look, or with a question when it needs something from him (purple, and the box gets a purple edge). He answers in the same box.
- A new version is a proposal: the draft keeps its text until he presses "Use this version". The next message works on the last proposal, used or not (11-nov).
- Every version is kept: the first draft, each rewrite, each hand edit. v1, v2, v3 sit above the conversation; clicking one puts it back. "Show changes" marks what the current version changed against the one before.
- The agent never posts or saves anywhere; it only returns text.

Not built yet: one conversation for a whole batch (all of Tuesday's updates at once), and "Remember this", to keep a correction as a rule of the ritual.

## In the inbox

The results panel after "Apply" shows what was done and what needs him. The drafts it produced go straight to this section, and the panel says how many were added, with a button to open them.

## What each draft says

- `where` is one word: Linear, Slack, GitHub, Mail or Other.
- `note` is one line saying what to do with the text, for example "send only if he missed the weekly".
- `text` is only what he pastes.

## Open

- Whether archived drafts are kept forever or cleared after a while. Proposed: kept, hidden by default.
