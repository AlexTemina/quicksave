# Design system

Native macOS, sober. Light and dark mode come from the system's semantic colors.

- Layer 1, tokens: spacing, radii, colors, text styles and sizes, all in one place in the app. Nothing else defines a value.
- Layer 2, components: card, pill, dot, label, icon button, Linear and Orca buttons, column, banner, decision button, key hint, bullet list, note, empty state. Built only from tokens.
- Screens use components and tokens, never raw styling. Changing the look of the whole app is changing the tokens.
- State colors are Linear's own, read live from the workspace.

## Links and hover cards

- Every link in the app is one component: it opens the link and, when the pointer rests on it for 0.8 s, shows a hover card. Links inside text get the same card. No screen opens a link by hand.
- Linear issue: the code, the state in its color, the title, assignee, due date, priority, project, labels and the start of the description.
- GitHub pull request: number, state, title, author, CI, review state, the size of the change and the start of the description.
- Any other web page: its site, title and summary. Wikipedia through its own summary service.
- Slack links get no card yet: reading Slack fast needs a token the app does not have.
- The card hides a moment after the pointer leaves, unless the pointer moved onto it. Each link is read once per session. A link with a card has no tooltip.
