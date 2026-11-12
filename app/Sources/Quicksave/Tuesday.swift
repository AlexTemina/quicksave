import SwiftUI

/// Tuesday closes Alan's week (Wednesday to Tuesday), and two things are due every Tuesday, whatever else the day holds:
/// the crew's Linear status updates before 14:00, when the Spain area weekly flow reads them, and the SFA in the
/// afternoon. Quicksave shows both on Today and drafts them with an agent; he reviews and posts them himself.
/// On 20-oct the Tuesday plan had neither, and on 10-nov Quicksave did not know about them.
/// The initiative update comes second: it rolls up the project updates, which he posts first.
enum Ritual: String, CaseIterable, Identifiable {
    case projectUpdates = "Project updates"
    case initiativeUpdate = "Initiative update"
    case sfa = "Weekly SFA"
    /// The reply in the thread of the posted SFA that says how last week's A+ went. It comes after the SFA (11-nov).
    case previously = "SFA previously"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .projectUpdates: return "Project updates"
        case .initiativeUpdate: return "Initiative update"
        case .sfa: return "Weekly SFA"
        case .previously: return "Previously, on my SFA"
        }
    }
    var when: String {
        switch self {
        case .projectUpdates: return Ritual.isTuesday ? "Before 14:00: the Spain area weekly flow reads them then. Post these first." : "They were due on Tuesday and are not all in Linear yet."
        case .initiativeUpdate: return Ritual.isTuesday ? "After the project updates: it rolls them up. Also before 14:00." : "It was due on Tuesday and is not in Linear yet."
        case .sfa: return Ritual.isTuesday ? "In the afternoon, in #org_alaner-sfa." : "It was due on Tuesday and is not in #org_alaner-sfa yet: post it today."
        case .previously: return "Reply in your SFA's thread with how last week's A+ went."
        }
    }
    /// What the box above "Draft it" suggests he writes.
    var hint: String {
        switch self {
        case .projectUpdates: return "What they must say: a project at risk, a date that moved, a win to highlight, who to thank…"
        case .initiativeUpdate: return "What the initiative update must carry: the headline of the week, a risk, a decision…"
        case .sfa: return "Your suns, fires and A+ of the week, in your own words. The agent fills in the rest."
        case .previously: return "How last week's A+ went, if you know better than Linear and Slack: done, half done, dropped…"
        }
    }
    var icon: String {
        switch self {
        case .projectUpdates: return "chart.bar.doc.horizontal"
        case .initiativeUpdate: return "flag.2.crossed"
        case .sfa: return "sun.max"
        case .previously: return "arrowshape.turn.up.backward"
        }
    }

    static var isTuesday: Bool { Calendar.current.component(.weekday, from: Date()) == 3 }

    /// The start of the last Tuesday, today included: the rituals of the week that closed then are due from that moment.
    static var tuesday: Date {
        let today = Calendar.current.startOfDay(for: Date())
        let back = (Calendar.current.component(.weekday, from: today) - 3 + 7) % 7
        return Calendar.current.date(byAdding: .day, value: -back, to: today) ?? today
    }

    /// When each ritual was posted since the last Tuesday, as the app last found it (Linear, Slack, or his "Posted").
    static func postedSaved() -> [Ritual: Date] {
        guard let saved = Database.shared.value("ritual.posted", as: [String: Double].self),
              saved["week"] == tuesday.timeIntervalSince1970 else { return [:] }
        return Dictionary(uniqueKeysWithValues: allCases.compactMap { r in saved[r.rawValue].map { (r, Date(timeIntervalSince1970: $0)) } })
    }

    static func savePosted(_ posted: [Ritual: Date]) {
        var saved = Dictionary(uniqueKeysWithValues: posted.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) })
        saved["week"] = tuesday.timeIntervalSince1970
        Database.shared.setValue("ritual.posted", saved)
    }

    /// Drafts this ritual left since Tuesday, so its state survives closing the app and carries into Wednesday.
    func draftsToday(_ drafts: [DraftItem]) -> [DraftItem] {
        drafts.filter { $0.source == rawValue && $0.created >= Ritual.tuesday }
    }

    /// The rituals not posted since the last Tuesday. Posted is what Linear and Slack show, never an archived draft: on
    /// 11-nov he archived the SFA draft without posting it, and the card went away.
    static func due(posted: [Ritual: Date]) -> [Ritual] { allCases.filter { posted[$0] == nil } }
}

struct SFAPostedResult: Decodable { let posted: Bool; let when: String?; let link: String?; let previously: Bool?; let previouslyWhen: String? }

extension AgentJob {
    /// Looks in #org_alaner-sfa for his SFA since a moment. Only reads.
    static func sfaPosted(since: Date) -> AgentJob {
        let day = ISO8601DateFormatter().string(from: since)
        return AgentJob(
            name: "sfa posted",
            directory: NSTemporaryDirectory(),
            prompt: """
            Did Alejandro Temina (alex.temina@alan.eu) post his weekly SFA (Suns, Fires, A+) in the Slack channel #org_alaner-sfa after \(day)?

            - Load the Slack tools first with ToolSearch (select:mcp__claude_ai_Slack__slack_search_public_and_private,mcp__claude_ai_Slack__slack_read_channel).
            - Search for messages from him in that channel after that day, or read the channel's recent messages. A top-level message from him there counts; a reply in someone else's thread does not.
            - Read only. Never send, draft or schedule anything.

            - If it is posted, read its thread: did he reply there with the recap that starts ":back: Previously, on my SFA..." (or similar "Previously" wording)?

            Return posted (true or false), when (ISO 8601) and link (the message's URL) if posted, previously (true or false) and previouslyWhen (ISO 8601) for the thread reply.
            """,
            model: "claude-haiku-5-5",
            allowed: ["ToolSearch", "mcp__claude_ai_Slack__slack_search_public_and_private", "mcp__claude_ai_Slack__slack_read_channel",
                      "mcp__claude_ai_Slack__slack_search_channels", "mcp__claude_ai_Slack__slack_search_users"],
            denied: ["mcp__claude_ai_Slack__slack_send_message", "mcp__claude_ai_Slack__slack_send_message_draft",
                     "mcp__claude_ai_Slack__slack_schedule_message", "Bash", "Write", "Edit"],
            schema: """
            {"type":"object","properties":{"posted":{"type":"boolean"},"when":{"type":"string"},"link":{"type":"string"},"previously":{"type":"boolean"},"previouslyWhen":{"type":"string"}},"required":["posted"]}
            """,
            maxTurns: 10)
    }
}

struct RitualResult: Decodable {
    struct DraftOut: Decodable {
        let place: String
        let note: String?
        let link: String?
        let text: String
        enum CodingKeys: String, CodingKey { case place = "where", note, link, text }
    }
    let drafts: [DraftOut]
    let notes: String?
}

extension AgentJob {
    static let ritualReads = ["Read", "Grep", "Glob", "ToolSearch", "Skill", "Bash(date:*)", "Bash(git log:*)",
                              "Bash(gh api:*)", "Bash(gh pr view:*)", "Bash(gh pr list:*)",
                              "mcp__claude_ai_Linear__get_initiative", "mcp__claude_ai_Linear__list_initiatives",
                              "mcp__claude_ai_Linear__get_status_updates", "mcp__claude_ai_Linear__list_users",
                              "mcp__claude_ai_Notion__notion-fetch", "mcp__claude_ai_Notion__notion-search",
                              "mcp__claude_ai_Slack__slack_read_channel", "mcp__claude_ai_Slack__slack_read_thread",
                              "mcp__claude_ai_Slack__slack_search_public_and_private", "mcp__claude_ai_Slack__slack_search_channels",
                              "mcp__claude_ai_Slack__slack_search_users"] + Morning.readLinear
    static let ritualNever = Morning.neverPost + ["mcp__claude_ai_Linear__save_status_update", "mcp__claude_ai_Linear__save_issue",
                                                  "mcp__claude_ai_Linear__save_project", "mcp__claude_ai_Linear__save_initiative",
                                                  "mcp__claude_ai_Slack__slack_send_message_draft", "Edit", "Write",
                                                  "Bash(git commit:*)", "Bash(git push:*)", "Bash(orca linear save-issue:*)"]
    static let ritualSchema = """
    {"type":"object","properties":{"drafts":{"type":"array","items":{"type":"object","properties":{"where":{"type":"string","enum":["Linear","Slack","Other"]},"note":{"type":"string"},"link":{"type":"string"},"text":{"type":"string"}},"required":["where","text"]}},"notes":{"type":"string"}},"required":["drafts"]}
    """

    /// `projectDrafts`: for the initiative update, the project updates drafted today, as they read now in Quicksave.
    /// `input`: what he wrote in the box before drafting.
    static func ritual(_ r: Ritual, projectDrafts: [DraftItem] = [], input: String = "", sfaLink: String? = nil) -> AgentJob {
        let task: String
        switch r {
        case .projectUpdates:
            task = """
            Draft this week's Linear project status updates of the Spain Product crew, from Quicksave.

            Run Claude/commands/crew-weekly.md with the argument `dry-run`: one project status update per project he writes. Do not draft the initiative update: that is a second step, once these are posted.

            Return one draft per project update: where "Linear", note "Project update: <project>, health <on track|at risk|off track>", link the project's Linear URL, text the update body exactly as it would be posted.
            """
        case .initiativeUpdate:
            let drafts = projectDrafts.map { "\($0.note)\n<<<\n\($0.body)\n>>>" }.joined(separator: "\n\n")
            task = """
            Draft this week's initiative update of the Spain Product crew, from Quicksave: run Claude/commands/initiative-weekly.md with `dry-run`.

            Roll it up from this week's project status updates as posted in Linear, and from Rémi's posted Concierge update if there is one (if it is missing, say so in notes). For a project whose update this week is not posted yet, use its draft below instead, and name it in notes so he posts it first.

            Project update drafts from Quicksave, as they read now:
            \(drafts.isEmpty ? "(none)" : drafts)

            Return one draft: where "Linear", note "Initiative update: <name>, health <on track|at risk|off track>", link the initiative's Linear URL, text the update body exactly as it would be posted.
            """
        case .sfa:
            task = """
            Draft this week's SFA (Suns, Fires, A+), from Quicksave: follow Claude/commands/write-sfa.md.
            Differences: do not save it to Journal/ (another step archives it when he posts) and never post it.
            Return one draft: where "Slack", note "Weekly SFA", link the URL of #org_alaner-sfa found with the Slack channel search, text the SFA ready to paste.
            Do not draft the "Previously, on my SFA" thread reply: that is another step, once the SFA is posted.
            """
        case .previously:
            task = """
            Draft the "Previously, on my SFA" reply, which Alejandro posts in the thread of this week's SFA, from Quicksave.

            This week's SFA, already posted: \(sfaLink ?? "find it: his latest top-level message in #org_alaner-sfa")
            It looks back at the A+ (the priorities) he set in his previous SFA, the one he posted the week before in #org_alaner-sfa (also archived in the vault as Journal/<date> -- Weekly SFA.md): for each one, did it happen? Check with Linear, GitHub and Slack, and with this week's SFA.

            The exact form, as in his past ones:
            ```
            :back: _Previously, on my SFA..._

            - :white_check_mark: [P0] <the A+ in a few words>: <what happened, one short sentence>.
            - :large_yellow_circle: [P1] <...>: <partly: what is done and what carries over>.
            - :red_circle: [P1] <...>: <not done, and why in a few words>.
            ```
            One line per A+ of the previous SFA, in its order, with its priority. :white_check_mark: done, :large_yellow_circle: partly, :red_circle: not done.

            Return one draft: where "Slack", note "Previously recap: reply in your SFA's thread", link the URL of this week's SFA message (so it lands in its thread), text ready to paste.
            """
        }
        return AgentJob(
            name: r.rawValue.lowercased(),
            directory: NSHomeDirectory() + "/vault",
            prompt: """
            \(task)

            What Alejandro wants in it, in his own words. It comes first: build the draft around it, and use what you read to complete and check it. If something you read contradicts it, keep his version and say so in notes.
            <<<
            \(input.isEmpty ? "Nothing: draft it from what you read." : input)
            >>>

            Rules:
            - Never post, never send, never save anything in Linear, Slack or the vault. You only return drafts; Alejandro reviews and posts them himself.
            - English, no em-dashes, every code with a 2-3 word tag.
            - The Linear, Slack and Notion tools are deferred: find them first with ToolSearch, then call them.
            - In a shell, one simple command per call: no `cd`, no `&&`, no pipes.
            - notes: only what he must know or act on (a missing update, a source that failed), one or two sentences, or empty.
            """,
            model: "claude-sonnet-5-5",
            allowed: ritualReads,
            denied: ritualNever,
            schema: ritualSchema,
            maxTurns: 120)
    }
}

/// On Tuesdays, at the top of Today: the two rituals of the end of Alan's week, with a button to draft each one.
struct TuesdayCard: View {
    @ObservedObject var store: Store
    /// Steps whose box is open: "Draft it" opens it, and the agent starts from the box's own button.
    @State private var composing: Set<Ritual> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                QSLabel(Ritual.isTuesday ? "Tuesday: the week closes" : "Left from Tuesday", icon: "calendar.badge.clock", accent: true)
                Text("It goes away once each one is posted: Linear and Slack say so, not the drafts.")
                    .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
            }
            // On Tuesday every step shows, posted ones ticked; later in the week only what is still missing.
            ForEach(Ritual.isTuesday ? Ritual.allCases : Ritual.due(posted: store.ritualPosted)) { row($0) }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.xl).fill(Theme.Palette.raised)
            .shadow(color: Theme.Palette.shadow, radius: 6, y: 2))
    }

    private func row(_ r: Ritual) -> some View {
        let posted = store.ritualPosted[r]
        // Drafts still open: an archived one that was never posted does not count.
        let drafts = r.draftsToday(store.drafts)
        let running = store.ritualsRunning.contains(r)
        let waiting = (r == .initiativeUpdate && store.ritualPosted[.projectUpdates] == nil
            && Ritual.projectUpdates.draftsToday(store.drafts + store.archivedDrafts).isEmpty)
            || (r == .previously && store.ritualPosted[.sfa] == nil)
        let missing = r == .projectUpdates && !store.ritualMissing.isEmpty ? " Still missing: " + store.ritualMissing.joined(separator: ", ") + "." : ""
        let text: String = {
            if let posted { return "Posted " + posted.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()) + "." }
            if running { return "An agent is drafting it from the vault, Linear, GitHub and Slack. It takes a few minutes." }
            if !drafts.isEmpty { return "\(drafts.count) draft\(drafts.count == 1 ? "" : "s") ready. Review and post them yourself." + missing }
            if waiting {
                return r == .previously ? "After the SFA: once it is posted, this reply goes in its thread."
                    : "Second step: draft and post the project updates first, then this one rolls them up."
            }
            if (r == .sfa || r == .previously) && store.sfaChecking { return r.when + " Looking in Slack…" }
            return r.when + missing
        }()
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                Image(systemName: posted == nil ? r.icon : "checkmark.circle.fill")
                    .foregroundStyle(posted == nil ? Theme.Palette.accent : Theme.Palette.agentIdle)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title).font(Theme.Text.cardTitle)
                    Text(text).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = store.ritualNotes[r], posted == nil {
                        Text(note).font(Theme.Text.micro).foregroundStyle(Theme.Palette.warning).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if posted == nil {
                    if running { ProgressView().controlSize(.small) }
                    else if !drafts.isEmpty {
                        Button { store.tab = .drafts } label: { Label("Open Drafts", systemImage: "square.and.pencil") }
                            .buttonStyle(QSHoverStyle()).foregroundStyle(Theme.Palette.accent)
                    } else {
                        if !composing.contains(r) {
                            Button { composing.insert(r) } label: { Label("Draft it", systemImage: "wand.and.stars") }
                                .buttonStyle(QSHoverStyle()).foregroundStyle(waiting ? Theme.Palette.textTertiary : Theme.Palette.accent)
                                .disabled(waiting)
                        }
                    }
                    Button { store.markPosted(r) } label: { Label("Posted", systemImage: "checkmark") }
                        .buttonStyle(QSHoverStyle()).foregroundStyle(Theme.Palette.textSecondary)
                        .help("Already posted: the app did not see it. Ticks it for this week.")
                }
            }
            if posted == nil && drafts.isEmpty && !waiting && (running || composing.contains(r)) {
                inputBox(r, sent: running)
                if !running {
                    HStack {
                        Spacer()
                        Button("Cancel") { composing.remove(r) }.buttonStyle(QSHoverStyle()).foregroundStyle(Theme.Palette.textSecondary)
                        QSPrimaryButton(title: "Draft it", icon: "wand.and.stars", busy: false, enabled: true) {
                            composing.remove(r)
                            Task { await store.draftRitual(r) }
                        }
                    }
                    .padding(.leading, 20 + Theme.Space.m)
                }
            }
        }
    }

    /// What he wants in the draft, written before the agent starts, like his comments before the morning plan.
    @ViewBuilder
    private func inputBox(_ r: Ritual, sent: Bool) -> some View {
        let text = store.ritualInput[r] ?? ""
        Group {
            if sent {
                // Sent already: shown as text, so it can still be selected and copied.
                Text(text.isEmpty ? "Nothing added." : text)
                    .font(Theme.Text.body)
                    .foregroundStyle(text.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Space.m)
                    .textSelection(.enabled)
            } else {
                TextEditor(text: Binding(get: { store.ritualInput[r] ?? "" }, set: { store.setRitualInput(r, $0) }))
                    .font(Theme.Text.body)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Space.s)
                    .frame(minHeight: 60, maxHeight: 120)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(r.hint).font(Theme.Text.body).foregroundStyle(Theme.Palette.textTertiary)
                                .padding(.horizontal, Theme.Space.s + 5).padding(.vertical, Theme.Space.s)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.well))
        .padding(.leading, 20 + Theme.Space.m)
    }
}
