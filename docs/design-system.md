# Design system

Native macOS, sober. Light and dark mode come from the system's semantic colors.

- Layer 1, tokens: spacing, radii, colors, text styles and sizes, all in one place in the app. Nothing else defines a value.
- Layer 2, components: card, pill, dot, label, icon button, Linear and Orca buttons, column, banner, decision button, key hint, bullet list, note, empty state. Built only from tokens.
- Screens use components and tokens, never raw styling. Changing the look of the whole app is changing the tokens.
- State colors are Linear's own, read live from the workspace.

## Tabs and what is new (12-nov)

- The tabs on top (Today, Inbox, Reviews, Drafts) say how many items each has and, in a red macOS-style badge (just the number), how many are new since he last looked at that tab.
- New means an item he has not seen in that tab: a new piece, side quest or collectible, or a card that moved, in Today; a new card in Inbox; a new pull request, reply or commit in Reviews; a new draft in Drafts.
- The tab in front, with the window active, has nothing new. Replies and commits in Reviews stay new until he opens that pull request.

## Talking to the AI (11-nov)

Every place where he writes a prompt and an AI acts uses one conversation, so they all look and behave the same:

- On top, one sentence: what the AI does there and what it may touch.
- His messages on the right, the AI's on the left. A question from the AI is purple and gives the box a purple edge until he answers.
- While it works, what it is doing right now in a few words ("Reading Linear", "Reading Slack", "Writing the answer"), read live from the agent.
- What it proposes (a text, a plan) shown as it will look, with one button that says exactly what accepting does. Nothing is used or written before that button.
- Optional quick buttons with ready-made messages.
- The box: Return sends, Shift-Return adds a line. It grows with the text, then scrolls.

Built so far in Drafts. Next: Tuesday's rituals, the morning, the inbox.

## Links and hover cards

- Every link in the app is one component: it opens the link and, when the pointer rests on it for 0.8 s, shows a hover card. Links inside text get the same card. No screen opens a link by hand.
- Linear issue: the code, the state in its color, the title, assignee, due date, priority, project, labels and the start of the description.
- GitHub pull request: number, state, title, author, CI, review state, the size of the change and the start of the description.
- Any other web page: its site, title and summary. Wikipedia through its own summary service.
- Slack links get no card yet: reading Slack fast needs a token the app does not have.
- The card hides a moment after the pointer leaves, unless the pointer moved onto it. Each link is read once per session. A link with a card has no tooltip.
