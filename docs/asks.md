# Asked of me (18-nov)

A tab with every place someone asked Alejandro something by name, whether he already answered there, and the card that follows it up.

Added on 18-nov, when Iván's discussion on the Clinic member experience (#35599) closed that same evening and its card sat among 33 side quests, with nothing saying someone was waiting.

## What it shows

- One row per ask: where it comes from (Discussion, Pull request, GitHub issue, Linear, Slack, Mail, Notion), who asked, when, the place (discussion title, channel, mail subject), and the line where they name him.
- The deadline the person set, in their words, when the source has one ("I want to close this discussion by Wed, 18 Nov EOD").
- **You answered**: he wrote at the source after the last time they named him. The row moves to "Answered or closed", folded.
- The card that follows it up, with its kind, code and state, linked to Linear. A card that names the discussion in its title ("Read and answer #35599") wins over one that only links it, and an open card over a closed one.
- **Create card** when there is none: it files a TEMI card in Todo, due today, high priority, with kind Answer (Review for a pull request that asks for a review), who asked, the ask, the deadline and the link. For a discussion it adds `/discussion-copilot <n>`.
- **Hide**, on hover: not for him, or answered somewhere else. Remembered in the app's local database; an eye button shows the hidden ones again.
- The tab's count is what is still waiting on him: not answered and with no closed card.

## Where it reads

- **GitHub**, live, every five minutes: his notifications of the last two weeks with reason "mention", in discussions, pull requests and issues. For each, the whole thread, to find the last post that names him and whether he posted after. Pull requests that only request his review stay in [Reviews](reviews.md).
- **Linear**, live, every five minutes: his notifications of the last two weeks that mention him in an issue or a comment, and whether he commented on that issue afterwards.
- **Slack, Gmail and Notion**, through a background agent on Haiku every thirty minutes: mentions and direct messages in Slack, mail from people that asks him something, Notion comments that name him. It also checks again the asks still open from before. Read only: it never sends, drafts, reacts or comments. Its asks are kept in the local database for two weeks.
- The cards: his TEMI issues updated in the last 30 days, open or closed.

## Writing

Create card is the one write: a new TEMI issue, through Orca like every other write of the app. Nothing else in this tab touches Linear.

## Open

- Notion mentions are best effort: the Notion tools find pages and comments, not "mentions of me" as such.
