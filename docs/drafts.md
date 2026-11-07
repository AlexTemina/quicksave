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

## In the inbox

The results panel after "Apply" shows what was done and what needs him. The drafts it produced go straight to this section, and the panel says how many were added, with a button to open them.

## What each draft says

- `where` is one word: Linear, Slack, GitHub, Mail or Other.
- `note` is one line saying what to do with the text, for example "send only if he missed the weekly".
- `text` is only what he pastes.

## Open

- Whether archived drafts are kept forever or cleared after a while. Proposed: kept, hidden by default.
