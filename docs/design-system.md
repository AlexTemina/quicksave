# Design system

Native macOS, sober. Light and dark mode come from the system's semantic colors.

- Layer 1, tokens: spacing, radii, colors, text styles and sizes, all in one place in the app. Nothing else defines a value.
- Layer 2, components: card, pill, dot, label, icon button, Linear and Orca buttons, column, banner, decision button, key hint, bullet list, note, empty state. Built only from tokens.
- Screens use components and tokens, never raw styling. Changing the look of the whole app is changing the tokens.
- State colors are Linear's own, read live from the workspace.
