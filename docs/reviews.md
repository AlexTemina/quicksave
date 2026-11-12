# Reviews (built, in its first real test)

A tab next to Today and Inbox with the pull requests that wait for Alejandro's review. Each one opens a detail where an agent has already done the groundwork: context, a pre-pass of comments, the code's flow and a worktree ready in VS Code. He shapes the review there, by typing or dictating, and publishes it from the app. He never has to open the pull request on GitHub.

It moves the vault's `pr-review-copilot` and `code-flow` skills into the app. They keep the same rule: he owns the review, and nothing reaches GitHub unless he presses the button.

## The list

- Pull requests of alan-apps where his review is requested by name. Requests sent to his team do not count.
- Each row: title, author, size, age, and the linked Linear issue when there is one.
- Each row also shows how many people are asked to review. Pull requests with many reviewers (the usual six) go in their own group, below the ones that are really his.
- The count of pending reviews sits in the menu bar, next to the inbox count.
- A pull request leaves the list when his review is no longer requested: he published it, it was merged or closed, or he was removed as a reviewer.

## Start review

A button on each row starts a [background agent](background-agents.md). It runs on its own and does what the copilot does today:

- Creates the review worktree in Orca and checks out the branch, with the true diff against `origin/main`.
- Builds the context: vault first, then the pull request and its stack, Linear, Notion and Slack.
- Runs the pre-pass every time, with no question first. It looks at the product and the decisions taken more than at the code.
- Proposes a verdict (approve, comment, request changes) and a main comment.
- Builds the code's flow as a local page that the app shows. Nothing is published to claude.ai.

While it works, the row shows its state: running, ready or failed. The model is Opus 5.5.

## The detail

- **Top:** the pull request (title, author, size, a link to GitHub) and a paragraph of context: what it solves, the key decisions, and where to look hard.
- **Open in VS Code:** opens the worktree with the review profile. It is enabled only once the worktree is ready.
- **The flow:** the code-flow page, embedded, with its hover popups.
- **The review:** (the link to the emoji legend is not part of the text: it is added under the main comment when he publishes)
  - The proposed verdict, which he can change.
  - The main comment, the text that goes with the approval or the request for changes. It is editable.
  - The list of comments: file and line, the emoji picker (🔧 ❓ ⚠️ 🤔 🍖 👍 and the rest of the legend), editable text, and a way to drop each one.
- **His notes:** a big text box to dictate into with Whisperflow while he reads the code. "Apply my notes" passes the notes to an agent (Sonnet 5.5). The agent adds comments and changes the text or emoji of existing ones, including the main comment. He sees each change in the list.

## Publishing

- The draft lives in Quicksave, not on GitHub. There is no pending review on GitHub.
- One button, "Publish review", posts everything kept: the verdict, the main comment and the inline comments. It never posts anything he has not accepted.
- After publishing, every item is clearly marked as published or not published. Comments he adds later can be published in a second review, and the published ones stay marked.
- This is the only place where Quicksave publishes anything, and it publishes only on his button.

## Worktrees

- Review worktrees are kept apart from work worktrees. They are children of one parent worktree in Orca, `⛔ PR reviews`, whose emoji says it must never be deleted.
- One child per pull request, named `Review PR <number>`, with the branch checked out and tracking its remote so the editor shows the pull request.
- When the pull request is merged or closed, Quicksave removes its worktree and forgets the review (decided 12-nov-2026).

## Not in this version

- Replies to the author's answers and re-reviews after new commits.
- Filing what the review taught about the domain into the vault. The copilot does this as its last step today: a vault pull request with how the product or component works, so the next review in the same domain starts with context. It stays out of the app for now.

## For development

- `QUICKSAVE_REVIEW=<number>` opens that pull request in Reviews at launch and starts its review once.
