import AppKit
import SwiftUI

/// The morning, inside the app: his comments, the day's Main Quest proposed and corrected until he approves it,
/// the game of the day and the standup, which lands in Drafts. See docs/morning.md.

/// A game used in a standup's simile. The log lives in the local database, so no game repeats.
struct GameEntry: Identifiable, Hashable {
    let id: Int64
    let date: String
    let score: String
    let game: String
    let simile: String
    let link: URL?
}

/// A game an agent offers for today.
struct GameOption: Decodable, Hashable, Identifiable {
    let game: String
    let link: String
    let simile: String
    var id: String { game }
    var url: URL? { URL(string: link) }

    /// Lowercase letters and digits of the title before any parenthesis: "Papers, Please" and "papers please" match.
    static func key(_ title: String) -> String {
        let base = title.components(separatedBy: "(").first ?? title
        return base.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

struct GameOptions: Decodable { let games: [GameOption] }

/// What the planning agent proposes. It is shown, corrected and approved; only then is anything written.
struct MorningPlan: Decodable {
    struct Piece: Decodable, Hashable {
        /// Empty for an issue that does not exist yet and will be created on approval.
        let id: String?
        let title: String
        let step: String
        let url: String?
        let team: String?
    }
    struct Discard: Decodable, Hashable { let what: String; let why: String }
    struct Side: Decodable, Hashable {
        let id: String; let title: String; let url: String?; let why: String
        /// The day's side quest from the middle of the pile.
        var slot: Bool? = nil
    }
    /// An issue of one of his projects, not his, worth a look today.
    struct Watch: Decodable, Hashable { let id: String; let title: String; let url: String?; let why: String }
    /// create a new Main Quest, move the due date of a slipped one, or keep the open one as it is.
    let action: String
    let existing: String?
    let goal: String
    let done: String
    let pieces: [Piece]
    let dueDate: String
    let why: String
    let discarded: [Discard]
    let meetings: [String]
    let failedSources: [String]
    let notes: String?
    /// What fits today beyond the Main Quest.
    let sideQuests: [Side]?
    /// From the projects he leads: what to look at today.
    var watch: [Watch]? = nil

    /// Something to write in Linear on approval: a new or moved Main Quest, or today's side quests.
    var writes: Bool { action != "keep" || !(sideQuests ?? []).isEmpty }

    var approveTitle: String {
        switch action {
        case "keep": return writes ? "Approve the side quests" : "Keep it"
        case "move": return "Approve and move the date"
        default: return "Approve and create"
        }
    }
}

struct MorningWriteResult: Decodable {
    var outcome: String
    var summary: String
    let identifier: String?
    let url: String?
    /// Kept by the app, so "Try again" only redoes what did not go through.
    var mainQuestDone: Bool? = nil
    var sideQuestsDone: Bool? = nil
}

struct StandupResult: Decodable {
    let text: String
    let threadLink: String?
    let notes: String?
}

enum Morning {
    static let repo = NSHomeDirectory() + "/dev/AlexTemina/quicksave"
    /// The only folder the write agent may write files in: descriptions it then hands to Linear.
    static let scratch: String = {
        // Not in the system's temporary folder: its path goes through a symlink, and the permission would not match.
        let path = NSHomeDirectory() + "/Library/Application Support/Quicksave/agent-files"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }()

    static var today: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.string(from: Date())
    }

    static var todayLong: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEEE d MMMM yyyy"
        return f.string(from: Date())
    }

    static let readLinear = ["mcp__claude_ai_Linear__whoami", "mcp__claude_ai_Linear__get_issue", "mcp__claude_ai_Linear__list_comments",
                             "mcp__claude_ai_Linear__list_issues", "mcp__claude_ai_Linear__list_milestones",
                             "mcp__claude_ai_Linear__get_milestone", "mcp__claude_ai_Linear__list_projects",
                             "mcp__claude_ai_Linear__get_project",
                             "Bash(orca linear list-issues:*)", "Bash(orca linear issue:*)", "Bash(orca linear list:*)",
                             "Bash(orca linear search:*)", "Bash(orca linear team list:*)", "Bash(orca linear project list:*)"]

    static let neverPost = ["mcp__claude_ai_Slack__slack_send_message", "mcp__claude_ai_Slack__slack_schedule_message",
                            "mcp__claude_ai_Gmail__send_message", "mcp__claude_ai_Gmail__reply",
                            "mcp__claude_ai_Linear__save_comment", "Bash(orca linear comment:*)", "Bash(rm:*)"]

    static let howToRun = """
    How to run commands, because you work with a short list of allowed actions and anything that does not match it is refused:
    - One simple command per call. No `cd`, no `&&` or `;`, no pipes, no heredocs, no redirections.
    - Linear, Slack and calendar tools are deferred: find them first with ToolSearch (for example select:mcp__claude_ai_Linear__get_issue), then call them. Do not say you have no access before trying.
    """
}

extension AgentJob {
    /// Proposes the day's Main Quest. It reads Linear, the weekly contract and his work calendar, and writes nothing.
    static func morningPlan(comments: String, rounds: [(plan: String, correction: String)], window: String) -> AgentJob {
        let history = rounds.isEmpty ? "None: this is the first proposal." : rounds.enumerated().map { i, r in
            "Proposal \(i + 1):\n\(r.plan)\nHis correction: \(r.correction)"
        }.joined(separator: "\n\n")
        return AgentJob(
            name: "morning plan",
            directory: Morning.repo,
            prompt: """
            You propose Alejandro's Main Quest for today, from the Morning panel of Quicksave. Today is \(Morning.todayLong).

            Read .claude/skills/quicksave-main-quest/SKILL.md, docs/main-quest.md and docs/linear-writing.md in this folder, and follow steps 1 to 5 of the skill. These differences apply:
            - You never write anything. After he approves the plan in the app, another job writes it to Linear.
            - Do not ask questions. Step 2's question is already answered by his comments below. If something is unclear, choose and say so in `notes`.
            - The result is the structured object, not a screen of text. Write it in English, because the app is in English: short sentences, no em-dashes, and every code with its 2-3 word tag, like `ES-12785 (30-day invitations)`.
            - The weekly contract is the newest file matching ~/vault/Journal/*Weekly Contract.md. Read it only.
            - The calendar: Google Calendar's list_events, which is his work account. Only today, in one call: startTime "\(Morning.today)T00:00:00", endTime "\(Morning.today)T23:59:00", orderBy "startTime", pageSize 50. Never Notion Calendar: it answers with every calendar at once and the result is too large to read.
            - His open issues come in pages. With list_issues, keep passing the cursor until hasNextPage is false, or use `orca linear list-issues --assignee me --json`, which returns them all. Never decide from the first page only.
            - When his comments link something (a Slack thread, a Linear issue, a pull request), open it before deciding: it is there because it matters today. Linear comments hold meeting notes and decisions: read them when an issue's state depends on them.

            His comments for today:
            <<<
            \(comments.isEmpty ? "None." : comments)
            >>>

            \(window)
            \(Ritual.due(posted: Ritual.postedSaved()).contains(.sfa) && !Ritual.isTuesday ? "\nThe weekly SFA was due on Tuesday and is not posted yet. Count about half an hour for it as busy time today and say so in notes. Quicksave drafts it from Today; it is not a side quest.\n" : "")\(Ritual.isTuesday ? "\nToday is Tuesday, the last day of Alan's week. Two things are due today whatever else happens: the Linear weekly status updates of his projects and the crew initiative, before 14:00, and the weekly SFA in the afternoon. Count about an hour for each as busy time, like meetings, when you size the side quests, and say so in notes. Quicksave drafts them from Today; they are not side quests.\n" : "")
            Earlier proposals today and his corrections, oldest first. When there are any, start from the last proposal and apply every correction:
            \(history)

            \(Morning.howToRun)

            The fields:
            - action: keep when a Main Quest is open and in date (return it as it is, with the pieces left), move when one is open but past its due date (propose the new due date), create when none is open.
            - existing: the identifier of the open Main Quest, for keep and move.
            - goal: one sentence. done: what "done" means, one sentence.
            - pieces: in order. id is the issue's identifier and url its link; for an issue that does not exist yet, leave id empty and set team. step is what this piece takes today, one short sentence.
            - dueDate: yyyy-MM-dd.
            - why: why this goal, one line. discarded: what you left out and why, one line each.
            - meetings: today's meetings, one line each, like "10:00 Spain weekly".
            - failedSources: every source you could not read, said plainly. Empty if all worked.
            - sideQuests: his other open issues that fit today next to the Main Quest, and only what fits. Work out the free time: his working day minus meetings minus what the Main Quest takes, and size each issue by its estimate or what it says. Rank by the 16-oct rule: something breaking now, then due today or overdue, then any date before no date and sooner first, then Linear priority, then size with small first. Never the Main Quest or its pieces, nothing labelled collectible, nothing in Pending for inputs. Each with id, title (a 2-3 word tag, without the code), url, and why in a few words (for example "due today, XS"). One of them is the medium slot (see the list above), with slot true.
            - discarded: every issue of the window that is not a piece or a side quest, by its code with its tag, and the reason in a few words ("waiting on Elise", "due 14-nov, no time today"). Nothing of the window may be missing.
            - watch: from his projects' list above, only what he should look at today. Each with id, title (2-3 word tag), url, and why ("overdue 3 days, Rémi's", "blocked on review"). Empty if all is on track.
            """,
            model: "claude-sonnet-5-5",
            allowed: ["Read", "Grep", "Glob", "ToolSearch", "Bash(date:*)",
                      "mcp__claude_ai_Google_Calendar__list_events", "mcp__claude_ai_Google_Calendar__get_event",
                      "mcp__claude_ai_Slack__slack_read_thread", "mcp__claude_ai_Slack__slack_read_channel",
                      "mcp__claude_ai_Slack__slack_search_public_and_private", "mcp__claude_ai_Slack__slack_search_channels",
                      "mcp__claude_ai_Slack__slack_search_users"]
                + Morning.readLinear,
            denied: Morning.neverPost + ["mcp__claude_ai_Linear__save_issue", "Bash(orca linear save-issue:*)",
                                         "Bash(orca linear relation:*)", "Bash(orca linear due-date:*)", "Bash(orca linear create:*)",
                                         "Bash(orca linear status:*)", "Edit", "Write",
                                         "mcp__claude_ai_Slack__slack_send_message_draft", "mcp__claude_ai_Google_Calendar__create_event",
                                         "mcp__claude_ai_Google_Calendar__update_event", "mcp__claude_ai_Google_Calendar__delete_event",
                                         "mcp__claude_ai_Google_Calendar__respond_to_event"],
            schema: """
            {"type":"object","properties":{"action":{"type":"string","enum":["create","move","keep"]},"existing":{"type":"string"},"goal":{"type":"string"},"done":{"type":"string"},"pieces":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"title":{"type":"string"},"step":{"type":"string"},"url":{"type":"string"},"team":{"type":"string"}},"required":["title","step"]}},"dueDate":{"type":"string"},"why":{"type":"string"},"discarded":{"type":"array","items":{"type":"object","properties":{"what":{"type":"string"},"why":{"type":"string"}},"required":["what","why"]}},"meetings":{"type":"array","items":{"type":"string"}},"failedSources":{"type":"array","items":{"type":"string"}},"notes":{"type":"string"},"sideQuests":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"title":{"type":"string"},"url":{"type":"string"},"why":{"type":"string"},"slot":{"type":"boolean"}},"required":["id","title","why"]}},"watch":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"title":{"type":"string"},"url":{"type":"string"},"why":{"type":"string"}},"required":["id","title","why"]}}},"required":["action","goal","done","pieces","dueDate","why","discarded","meetings","failedSources"]}
            """,
            maxTurns: 60,
            extraDirectories: [NSHomeDirectory() + "/vault"])
    }

    /// Writes the plan he approved to Linear: step 6 of the skill, and nothing more.
    static func morningWrite(plan: String) -> AgentJob {
        AgentJob(
            name: "morning write",
            directory: Morning.repo,
            prompt: """
            Alejandro approved this Main Quest plan in Quicksave a moment ago. Write it to Linear by following step 6 of .claude/skills/quicksave-main-quest/SKILL.md, and read docs/linear-writing.md first. Write exactly what the plan says, nothing else.

            The approved plan:
            \(plan)

            Rules:
            - Read the open Main Quest again first. If the plan says create and one is open, or it says move and the open one is a different issue, write nothing and return needs_you saying what you found.
            - Do not write the side quests: the app writes them into the description itself once you are done.
            - Pieces with an empty id are issues to create first, in their team, assigned to him, in Todo, with today's due date.
            - Never post a comment, and never change a piece's state, priority or labels.
            - If a write answers linear_write_unconfirmed, retry it with its --write-id. Never create again without it.
            - Read the Main Quest back at the end and check the label, due date and relations.

            The exact commands, so none is guessed:
            - Move a due date: `orca linear save-issue <id> --due-date <yyyy-mm-dd> --json`
            - Create the Main Quest: `orca linear save-issue --team TEMI --title "Main Quest: <goal>" --assignee me --label "Main Quest" --state "In Progress" --due-date <yyyy-mm-dd> --body-file "\(Morning.scratch)/main-quest.md" --json` (the quotes matter: the folder has a space), after writing the description to that file with the Write tool. A text with several lines never goes inside a command: the command is refused.
            - Create a missing piece: `orca linear save-issue --team <key> --title "<title>" --assignee me --state Todo --due-date <yyyy-mm-dd> --json`
            - Link a piece: `orca linear relation add <main quest> --related <piece> --type related --json`
            - Read an issue: `orca linear issue <id> --relations --json`
            If a command answers with an error, read its `--help` once and try again with the right form. Do not switch to other tools.

            \(Morning.howToRun)

            Return the structured result, in English: outcome (done, needs_you or failed), summary in one or two sentences, identifier and url of the Main Quest.
            """,
            model: "claude-sonnet-5-5",
            allowed: ["Read", "ToolSearch", "Bash(date:*)", "Write(/\(Morning.scratch)/**)", "Edit(/\(Morning.scratch)/**)",
                      "Bash(orca linear save-issue:*)", "Bash(orca linear relation add:*)",
                      "Bash(orca linear due-date set:*)", "Bash(orca linear team:*)"] + Morning.readLinear,
            denied: Morning.neverPost + ["Bash(orca linear status:*)", "Bash(orca linear priority:*)", "Bash(orca linear label:*)",
                                         "Bash(orca linear relation remove:*)"],
            schema: """
            {"type":"object","properties":{"outcome":{"type":"string","enum":["done","needs_you","failed"]},"summary":{"type":"string"},"identifier":{"type":"string"},"url":{"type":"string"}},"required":["outcome","summary"]}
            """,
            maxTurns: 50,
            extraDirectories: [Morning.scratch])
    }

    /// Offers five games for the standup's simile, none of them already used. It has no tools.
    static func games(mood: String, used: [String], offered: [String]) -> AgentJob {
        AgentJob(
            name: "games",
            directory: NSTemporaryDirectory(),
            prompt: """
            Offer Alejandro five videogames for today's standup. He opens it with a mood score and a videogame simile, and he picks the game.

            The day:
            <<<
            \(mood)
            >>>

            Rules:
            - Each game must match the real mood of the day: ramping with a mentor, grinding solo, a boss fight, exploring a new map, many plates at once, being low on energy.
            - Any era counts, from the Master System on. Retro classics are welcome. Prefer games he is likely to know: well known, not obscure indies.
            - Never a game from this list of games already used: \(used.joined(separator: "; "))
            - Not one of these either, he has already seen them today: \(offered.isEmpty ? "none" : offered.joined(separator: "; "))
            - Five games, all different from each other in feeling.
            - link: the game's English Wikipedia page, https://en.wikipedia.org/wiki/<Title_with_underscores>. Use a page you are sure exists.
            - simile: one or two sentences in English that tie the game to today, concrete enough that the team feels it. It follows "Feeling like playing <game>". No em-dashes.
            """,
            model: "claude-sonnet-5-5",
            allowed: ["Read"],
            denied: Morning.neverPost,
            schema: """
            {"type":"object","properties":{"games":{"type":"array","items":{"type":"object","properties":{"game":{"type":"string"},"link":{"type":"string"},"simile":{"type":"string"}},"required":["game","link","simile"]}}},"required":["games"]}
            """,
            maxTurns: 4)
    }

    /// Writes today's standup with the game he chose. It reads Slack and Linear, and only returns text.
    static func standup(plan: String, comments: String, score: String, game: GameOption) -> AgentJob {
        AgentJob(
            name: "standup",
            directory: NSTemporaryDirectory(),
            prompt: """
            Write Alejandro's standup for today, \(Morning.todayLong). He posts it himself as a reply in the thread of today's "Spain Area Standup" message in #area_spain. You only return the text.

            Today's Main Quest, which he approved:
            \(plan)

            His comments for today: \(comments.isEmpty ? "none" : comments)

            The game he chose: \(game.game) (\(game.link)). Its simile: \(game.simile)
            His score: \(score)

            What to read, only to get the facts right:
            - His last two standups in #area_spain (search for messages from him starting with ":coffee: Yo!"), to know what he promised yesterday and to match his voice.
            - His Linear issues that changed since his last standup, to see what got done or moved: list_issues with assignee "me".
            - Find today's "Spain Area Standup" parent message in #area_spain and put its link in threadLink. Leave it empty if it is not there yet.
            - The Slack and Linear tools are deferred: find them first with ToolSearch (for example select:mcp__claude_ai_Slack__slack_read_channel), then call them. Do not say you have no access before trying.

            The form, exactly:
            ```
            :coffee: Yo! :hi:

            :firecracker: \(score). Feeling like playing <LINK|GAME> <the simile, one or two sentences>.

            :done: <something completed since the last standup>
            :progress: <ongoing, on track>
            :yellowprogress: <ongoing, falling behind>

            :target: <the single focus of the day: the Main Quest's goal, said simply>

            :todo: <one per line>

            :paused-red: <a real blocker, or drop the line>
            ```

            Rules:
            - The :coffee: line is always exactly ":coffee: Yo! :hi:".
            - One item per line, always. Three things done are three :done: lines.
            - :done: is finished (an open PR with the work done counts). :progress: is on track. :yellowprogress: is behind. Do not call everything done.
            - Links in Slack syntax <url|text>, every code with a 2-3 word description: <https://linear.app/...|PLAY-5148: name resolution>.
            - Never meeting times in :todo:. "Coffee with Alfredo" is enough.
            - Drop empty sections. No filler.
            - English, no em-dashes, short and direct: one line per item, half a line if possible. The simile is the only longer line.
            - Use Slack mentions <@USERID> only when you found the id; a bare name is fine otherwise.

            Never send, schedule or draft a message. Return the structured result: text (ready to paste), threadLink, and notes (one short sentence on anything you could not check, or empty).
            """,
            model: "claude-sonnet-5-5",
            allowed: ["ToolSearch", "mcp__claude_ai_Slack__slack_search_public_and_private", "mcp__claude_ai_Slack__slack_search_public",
                      "mcp__claude_ai_Slack__slack_read_channel", "mcp__claude_ai_Slack__slack_read_thread",
                      "mcp__claude_ai_Slack__slack_search_channels", "mcp__claude_ai_Slack__slack_search_users"] + Morning.readLinear,
            denied: Morning.neverPost + ["mcp__claude_ai_Slack__slack_send_message_draft", "mcp__claude_ai_Linear__save_issue",
                                         "Bash(orca linear save-issue:*)"],
            schema: """
            {"type":"object","properties":{"text":{"type":"string"},"threadLink":{"type":"string"},"notes":{"type":"string"}},"required":["text"]}
            """,
            maxTurns: 30)
    }
}

// MARK: The panel

struct MorningView: View {
    @ObservedObject var store: Store
    @State private var correction = ""
    @State private var chosen: GameOption?
    @State private var score = "3/5"
    @State private var showHistory = false
    /// After approving, the panel moves to the standup; this goes back to look at the plan.
    @State private var viewingPlan = false

    private var onStandup: Bool { store.morningApproved && !viewingPlan }

    private var gateCount: Int { store.pendingCards.count }
    /// While Apply runs, Linear is changing under the plan: the morning waits, with no way around it.
    private var applying: Bool { store.applying }
    private var gated: Bool { applying || ((gateCount > 0 || store.approvedCount > 0) && !store.morningContinueAnyway) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.xl) {
                        if onStandup {
                            // Step 2, its own screen: the day is planned; the standup is optional.
                            approvedRow
                            if store.standupSkipped && !store.standupDone {
                                QSNote(text: "You skipped the standup today. You can still write it.")
                            }
                            gameStep
                            if store.standupDone { finished.id("done") }
                        } else {
                            auditorCard
                            if applying { applyingGate } else if gateCount > 0 || store.approvedCount > 0 { gate }
                            commentsStep
                            if store.morningProposing { working("An agent is reading Linear, the weekly contract and your calendar…") }
                            if let plan = store.morningPlan { planStep(plan) }
                        }
                        if let notice = store.morningNotice { QSNote(text: notice, icon: "exclamationmark.triangle", warning: true) }
                    }
                    .padding(Theme.Space.xl)
                    .textSelection(.enabled)
                    .id(onStandup)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: store.morningApproved) { if store.morningApproved { viewingPlan = false } }
                .onChange(of: store.standupDone) { if store.standupDone { withAnimation { proxy.scrollTo("done", anchor: .top) } } }
            }
        }
        .frame(width: Theme.Size.morningWidth)
        .frame(minHeight: 480, idealHeight: Theme.Size.morningHeight, maxHeight: Theme.Size.morningHeight)
        .onAppear { store.loadGameHistory() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Start the day", systemImage: Theme.Icon.morning).font(Theme.Text.heroTitle)
            Text(Morning.todayLong).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            HStack(spacing: Theme.Space.xs) {
                stepChip("1 Plan", current: !onStandup, enabled: store.morningApproved) { viewingPlan = true }
                Image(systemName: "chevron.right").font(Theme.Text.micro).foregroundStyle(Theme.Palette.textTertiary)
                stepChip("2 Standup", current: onStandup, enabled: store.morningApproved) { viewingPlan = false }
            }
            if store.morningPlan != nil || store.morningApproved {
                Button("Start over") { store.resetMorning(); chosen = nil; correction = "" }
                    .buttonStyle(QSHoverStyle()).font(Theme.Text.meta)
                    .disabled(store.morningBusy)
            }
            QSIconButton(systemImage: "xmark", help: "Close. What you did stays here until you start over.") { store.morningOpen = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Theme.Space.xl).padding(.vertical, Theme.Space.l)
    }

    private var applyingGate: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                ProgressView().controlSize(.small)
                Text("Apply is running. Wait until it finishes.").font(Theme.Text.cardTitle)
            }
            Text(store.applyStep.isEmpty ? "The agents are changing Linear, so a plan now would read it half done."
                                         : store.applyStep + " A plan now would read Linear half done.")
                .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.warning.opacity(0.10)))
    }

    private func stepChip(_ title: String, current: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.Text.micro)
                .foregroundStyle(current ? Theme.Palette.accent : Theme.Palette.textSecondary)
                .padding(.horizontal, Theme.Space.s).padding(.vertical, 3)
                .background(Capsule().fill(current ? Theme.Palette.highlight : .clear))
        }
        .buttonStyle(QSHoverStyle(padding: 0, backdrop: false))
        .disabled(!enabled || current)
    }

    /// The auditor in plain words: when it last read his sources (Slack, mail, GitHub, Linear, meetings) to bring new
    /// cards to the inbox, what it could not read, and a button to read them again now. It takes long (50 minutes on
    /// 10-nov), so the morning never waits for it.
    var auditorCard: some View {
        let status = store.auditor
        let running = status?.run?.running == true
        let failed = status?.failed ?? []
        let checked = status?.sources.filter(\.ok).compactMap(\.lastSwept).max()
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Image(systemName: running ? "arrow.triangle.2.circlepath" : failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(running ? Theme.Palette.accent : failed.isEmpty ? Theme.Palette.agentIdle : Theme.Palette.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(running ? "Reading your sources now…"
                         : checked.map { "Sources read " + QSDate.ago($0) } ?? (status == nil ? "Reading…" : "Sources never read"))
                        .font(Theme.Text.cardTitle)
                    Text(running
                         ? "The auditor started " + (status?.run?.started.map(QSDate.ago) ?? "just now") + ". What needs you will reach the Inbox when it finishes. You can plan meanwhile."
                         : failed.isEmpty
                            ? "The auditor reads Slack, mail, GitHub, Linear and meetings, and brings what needs you to the Inbox."
                            : "Could not read " + failed.map(\.name).joined(separator: ", ") + ", so the Inbox may be missing things from there.")
                        .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if let run = status?.run, let output = run.output, !running {
                    AuditorOutputButton(run: run, output: output)
                }
                if running { ProgressView().controlSize(.small) }
                else {
                    Button { Task { await store.sweepNow() } } label: { Label("Read again now", systemImage: "arrow.clockwise") }
                        .buttonStyle(QSHoverStyle()).foregroundStyle(Theme.Palette.accent)
                        .disabled(store.auditorStarting || status == nil)
                        .help("Runs the auditor now, in Orca. It takes a while, and the plan does not wait for it.")
                }
            }
            ForEach(failed) { s in
                Text("\(s.name), last read " + (s.lastSwept.map(QSDate.ago) ?? "never") + ": " + (s.error ?? "failed"))
                    .font(Theme.Text.micro).foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice = store.auditorNotice { QSNote(text: notice, icon: "exclamationmark.triangle", warning: true) }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.well))
    }

    private var gate: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            let parts = [gateCount > 0 ? "\(gateCount) cards to decide" : nil,
                         store.approvedCount > 0 ? "\(store.approvedCount) accepted and waiting for Apply" : nil].compactMap { $0 }
            QSNote(text: "Inbox first: " + parts.joined(separator: " and ") + ".", icon: Theme.Icon.inbox, warning: true)
            Text("The plan reads Linear, and what still sits in the inbox is not there yet.")
                .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: Theme.Space.m) {
                Button { store.morningOpen = false; store.tab = .inbox } label: { Label("Open Inbox", systemImage: Theme.Icon.inbox) }
                    .buttonStyle(QSHoverStyle()).foregroundStyle(Theme.Palette.accent)
                if !store.morningContinueAnyway {
                    Button("Continue anyway") { store.morningContinueAnyway = true }
                        .buttonStyle(QSHoverStyle()).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.warning.opacity(0.10)))
    }

    private var commentsStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            QSLabel("Your day", icon: "text.bubble")
            Text("What the calendar does not know: being away, little time, what you want to push.")
                .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
            if store.morningPlan != nil || store.morningProposing {
                // Sent already: shown as text, so it can still be selected and copied.
                Text(store.morningComments.isEmpty ? "No comments." : store.morningComments)
                    .font(Theme.Text.body)
                    .foregroundStyle(store.morningComments.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Space.m)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.well))
            } else {
                TextEditor(text: $store.morningComments)
                    .font(Theme.Text.body)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Space.s)
                    .frame(minHeight: 70, maxHeight: 110)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.well))
            }
            if store.morningPlan == nil {
                HStack {
                    Spacer()
                    QSPrimaryButton(title: "Propose the plan", icon: "wand.and.stars", busy: store.morningProposing,
                                    enabled: !gated && !store.morningProposing) {
                        Task { await store.proposePlan(correction: nil) }
                    }
                    .help(applying ? "Wait until Apply finishes." : gated ? "Clear the inbox first, or press Continue anyway." : "An agent proposes today's Main Quest. Nothing is written yet.")
                }
            }
        }
    }

    private func planStep(_ plan: MorningPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            QSDeckCard {
                HStack(spacing: Theme.Space.s) {
                    QSLabel(plan.action == "keep" ? "Main Quest, open" : plan.action == "move" ? "Main Quest, slipped" : "Main Quest, proposed",
                            icon: Theme.Icon.mainQuest, accent: true)
                    Label(QSDate.friendly(plan.dueDate), systemImage: Theme.Icon.due).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                    if let existing = plan.existing, !existing.isEmpty {
                        Text(existing).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                MD(plan.goal).font(Theme.Text.heroTitle).fixedSize(horizontal: false, vertical: true)
                MD("**Done:** " + plan.done).font(Theme.Text.body)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(Array(plan.pieces.enumerated()), id: \.offset) { i, piece in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                            Text("\(i + 1)").font(Theme.Text.number).foregroundStyle(Theme.Palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: Theme.Space.s) {
                                    if let id = piece.id, !id.isEmpty { Text(id).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary) }
                                    else { QSTag(text: "New in \(piece.team ?? "TEMI")", icon: "plus", color: Theme.Palette.accent) }
                                    MD(piece.title).font(Theme.Text.cardTitle)
                                    if let url = piece.url.flatMap(URL.init) { QSOpenLinkButton(url: url) }
                                }
                                MD(piece.step).font(Theme.Text.body).foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                    }
                }
                .padding(.vertical, Theme.Space.xs)
                MD("**Why:** " + plan.why).font(Theme.Text.body)
                if let sides = plan.sideQuests, !sides.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        QSLabel("Side quests that fit", icon: Theme.Icon.sideQuests)
                        QSBulletList(lines: sides.map { s in
                            let code = s.url.flatMap(URL.init).map { "[\(s.id)](\($0.absoluteString))" } ?? s.id
                            return "\(code) \(s.title): \(s.why)" + (s.slot == true ? " *(medium slot)*" : "")
                        })
                    }
                }
                if let watch = plan.watch, !watch.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        QSLabel("Your projects: worth a look", icon: "eye")
                        QSBulletList(lines: watch.map { w in
                            let code = w.url.flatMap(URL.init).map { "[\(w.id)](\($0.absoluteString))" } ?? w.id
                            return "\(code) \(w.title): \(w.why)"
                        })
                    }
                }
                let missing = store.morningWindow?.missing(from: plan) ?? []
                if !missing.isEmpty {
                    QSNote(text: "The plan does not mention " + missing.map { "\($0.identifier) (\($0.title))" }.joined(separator: ", ")
                           + ". Ask it to place them, or add them yourself.", icon: "exclamationmark.triangle", warning: true)
                }
                if !plan.discarded.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        QSLabel("Left out", icon: "tray.and.arrow.down")
                        QSBulletList(lines: plan.discarded.map { "\($0.what): \($0.why)" }, secondary: true)
                    }
                }
                if !plan.meetings.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        QSLabel("Today's meetings", icon: "calendar")
                        QSBulletList(lines: plan.meetings, secondary: true)
                    }
                }
                ForEach(plan.failedSources, id: \.self) { QSNote(text: "Could not read: \($0)", icon: "exclamationmark.triangle", warning: true) }
                if let notes = plan.notes, !notes.isEmpty { QSNote(text: notes) }
            }
            if store.morningApproved {
                approvedRow
            } else {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: Theme.Icon.correct).foregroundStyle(Theme.Palette.accent)
                    TextField("Correct it: swap the second piece, due tomorrow, Mo first…", text: $correction)
                        .textFieldStyle(.plain)
                        .padding(Theme.Space.s)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.well))
                        .disabled(store.morningProposing)
                        .onSubmit { revise() }
                    Button("Revise") { revise() }
                        .buttonStyle(QSHoverStyle()).foregroundStyle(Theme.Palette.accent)
                        .disabled(applying || store.morningProposing || correction.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack {
                    Text(plan.writes ? "Nothing is written in Linear until you approve."
                                     : "Nothing is written: the open Main Quest stays as it is.")
                        .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                    Spacer()
                    QSPrimaryButton(title: plan.approveTitle, icon: "checkmark", enabled: !applying && !store.morningProposing) {
                        Task { await store.approvePlan() }
                    }
                }
            }
        }
    }

    @ViewBuilder private var approvedRow: some View {
        if store.morningWriting {
            working("Writing it in Linear…")
        } else if let r = store.morningWritten {
            QSResultRow(icon: r.outcome == "done" ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                        color: r.outcome == "done" ? Theme.Palette.prOpen : Theme.Palette.warning,
                        title: r.identifier ?? "Linear", detail: r.summary, links: r.url.flatMap(URL.init).map { [$0] } ?? [])
            if r.outcome != "done" {
                HStack {
                    Spacer()
                    Button { Task { await store.writePlan() } } label: { Label("Try again", systemImage: "arrow.clockwise") }
                        .buttonStyle(QSHoverStyle()).foregroundStyle(Theme.Palette.accent)
                        .disabled(applying)
                }
            }
        } else {
            QSResultRow(icon: "checkmark.circle.fill", color: Theme.Palette.prOpen, title: "Plan", detail: "Approved. The open Main Quest stays as it is.")
        }
    }

    private func revise() {
        let text = correction.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !store.morningProposing, !applying else { return }
        correction = ""
        Task { await store.proposePlan(correction: text) }
    }

    private var gameStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                QSLabel("Game of the day", icon: "gamecontroller.fill", accent: true)
                Spacer()
                Picker("", selection: $score) {
                    ForEach(1...5, id: \.self) { Text("\($0)/5").tag("\($0)/5") }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 230)
                .help("How you feel today, out of five")
            }
            if store.gamesLoading && store.gameOptions.isEmpty { working("Looking for games that fit today…") }
            ForEach(store.gameOptions) { option in gameCard(option) }
            HStack(spacing: Theme.Space.m) {
                Button { Task { await store.loadGames() } } label: { Label("Five more", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(QSHoverStyle()).disabled(store.gamesLoading || store.standupWriting)
                if store.gamesLoading && !store.gameOptions.isEmpty { ProgressView().controlSize(.small) }
                Button { showHistory.toggle() } label: {
                    Label("Played before · \(store.gameHistory.count)", systemImage: showHistory ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(QSHoverStyle()).foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                if !store.standupDone {
                    Button("Skip the standup") { store.standupSkipped = true; store.morningOpen = false }
                        .buttonStyle(QSHoverStyle()).foregroundStyle(Theme.Palette.textSecondary)
                        .disabled(store.standupWriting)
                        .help("Close the panel without a standup today. The plan is already saved.")
                    QSPrimaryButton(title: "Write the standup", icon: "square.and.pencil", busy: store.standupWriting,
                                    enabled: chosen != nil && !store.standupWriting && !store.morningWriting) {
                        if let chosen { Task { await store.writeStandup(game: chosen, score: score) } }
                    }
                }
            }
            if showHistory { history }
        }
    }

    private func gameCard(_ option: GameOption) -> some View {
        let isChosen = chosen == option
        return Button { chosen = option } label: {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .font(Theme.Text.heroTitle)
                    .foregroundStyle(isChosen ? Theme.Palette.accent : Theme.Palette.textTertiary)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack(spacing: Theme.Space.s) {
                        Text(option.game).font(Theme.Text.cardTitle)
                        if let url = option.url {
                            QSOpenLinkButton(url: url, help: url.absoluteString)
                        }
                    }
                    Text(option.simile).font(Theme.Text.body).foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.m)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(isChosen ? Theme.Palette.highlight : .clear)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
        }
        .buttonStyle(QSHoverStyle(padding: 0, backdrop: false))
        .disabled(store.standupDone || store.standupWriting)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(store.gameHistory) { g in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                    Text(QSDate.friendly(g.date)).font(Theme.Text.code).foregroundStyle(Theme.Palette.textTertiary)
                        .frame(width: 92, alignment: .leading)
                    Text(g.score).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary).frame(width: 40, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Theme.Space.xs) {
                            Text(g.game).font(Theme.Text.cardTitle)
                            if let url = g.link {
                                QSOpenLinkButton(url: url, help: url.absoluteString)
                            }
                        }
                        Text(g.simile).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
                    }
                }
            }
        }
        .padding(Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.well))
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            QSResultRow(icon: "checkmark.circle.fill", color: Theme.Palette.prOpen, title: "Standup",
                        detail: "It is in Drafts, ready to leave in Slack." + (store.standupNotes.isEmpty ? "" : " " + store.standupNotes))
            HStack {
                Spacer()
                QSPrimaryButton(title: "Open Drafts", icon: "square.and.pencil") { store.morningOpen = false; store.tab = .drafts }
            }
        }
    }

    private func working(_ text: String) -> some View {
        HStack(spacing: Theme.Space.s) {
            ProgressView().controlSize(.small)
            Text(text).font(Theme.Text.body).foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}

/// What the auditor's last run said when it ended, in a popover: the sources it read and what it changed.
struct AuditorOutputButton: View {
    let run: Auditor.Run
    let output: String
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: { Label("What it said", systemImage: "text.bubble") }
            .buttonStyle(QSHoverStyle())
            .help("Read what the last run said when it ended")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(spacing: Theme.Space.s) {
                        QSLabel("Run \(run.number)", icon: "text.bubble", accent: true)
                        Text([run.manual ? "started by hand" : "scheduled", run.ended.map { "ended " + QSDate.ago($0) }]
                                .compactMap { $0 }.joined(separator: ", "))
                            .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    ScrollView {
                        MarkdownBlock(output).font(Theme.Text.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 460)
                }
                .padding(Theme.Space.l)
                .frame(width: 560)
            }
    }
}
