import AppKit
import Foundation

/// The Spain Eng on-call shift: the review he applies, the on-call Main Quest, one agent per card, and the watch for new
/// urgent work. See docs/oncall.md.

/// One card of the review: an issue of the on-call board, or a Slack call to the on-call with no issue yet.
struct OnCallProposal: Codable, Identifiable, Hashable {
    var id: String
    /// ES-123, or nil for a Slack call with no issue.
    var issue: String?
    var title: String
    var tag: String
    var url: String?
    var source: String
    var slackLink: String?
    var currentPriority: String
    var currentState: String
    var priority: String
    var state: String
    var parent: String?
    /// The parent it has now in Linear, which decides whether it goes in a group.
    var currentParent: String? = nil
    var typeLabel: String?
    var assignToMe: Bool
    var enters: Bool
    var why: String
    /// What he wrote on the card, sent with his next message to the agent.
    var correction: String = ""
    /// Changed by the agent after his last message, not looked at since.
    var touched = false
    var applied: Date? = nil
    var applyError: String? = nil
    /// Assigned to someone else: dropped for good, never shown or applied (18-nov).
    var discarded: Date? = nil
    var open: Bool { applied == nil && discarded == nil }

    var changesLinear: Bool {
        issue == nil ? enters : (priority != currentPriority || state != currentState || assignToMe
                                  || !(parent ?? "").isEmpty || !(typeLabel ?? "").isEmpty)
    }
}

struct OnCallReview: Codable {
    var created = Date()
    var items: [OnCallProposal] = []
    var summary = ""
    var chat: [ReviewChatTurn] = []
    var session: String? = nil
    var appliedAt: Date? = nil
    var cost: Double? = nil
}

/// A call to the on-call handles in Slack, found by the watch.
struct OnCallSlackCall: Codable, Hashable, Identifiable {
    var id: String { link.isEmpty ? when + author : link }
    let when: String
    let handle: String
    let author: String
    let channel: String
    let text: String
    let link: String
    let issue: String?
}

/// What the app keeps of the shift. Linear holds the issues and the on-call Main Quest; this is only the app's memory.
struct OnCallState: Codable {
    var review: OnCallReview? = nil
    var lastReview: Date? = nil
    /// His shift days from Alan Home (yyyy-MM-dd), and the day they were read.
    var shiftDays: [String] = []
    var shiftChecked: String? = nil
    /// Urgent issues already notified, so each one is told once.
    var notified: [String] = []
    var slackSince: Date? = nil
    var slackCalls: [OnCallSlackCall] = []
    /// Issues whose agent the app started, so it never starts two.
    var launched: [String] = []
    /// Parents whose children he chose to see as one card, with the name the card shows. Set by hand in the tab.
    var groups: [String: String] = [:]
    /// The day each group was last told on Telegram: once a day per group.
    var groupNotified: [String: String] = [:]
    /// Slack calls he marked as read.
    var seenCalls: [String] = []
    /// Titles of the parents the cards hang from, read from Linear, so a parent never shows as a bare code.
    var parentTitles: [String: String] = [:]
}

enum OnCall {
    static let team = "ES"
    static let label = "Eng Oncall"
    static let gate = "Technical Support"
    static let titlePrefix = "On-call shift"
    static let parentPrefix = "🚨 On-call"
    static let priorities = ["urgent", "high", "medium", "low", "none"]

    static var skill: String {
        let base = NSHomeDirectory() + "/.claude/plugins/marketplaces/alan-skills/alan-spain/skills/oncall"
        return base
    }

    /// Where the agents leave the texts he must post; the app moves them into Drafts.
    static let draftsFolder: String = {
        let path = NSHomeDirectory() + "/Library/Application Support/Quicksave/oncall-drafts"
        try? FileManager.default.createDirectory(atPath: path + "/imported", withIntermediateDirectories: true)
        return path
    }()

    static func saved() -> OnCallState { Database.shared.value("oncall", as: OnCallState.self) ?? OnCallState() }
    static func save(_ s: OnCallState) { Database.shared.setValue("oncall", s) }

    static func priorityName(_ n: Double?) -> String {
        switch Int(n ?? 0) { case 1: return "urgent"; case 2: return "high"; case 3: return "medium"; case 4: return "low"; default: return "none" }
    }

    static func shortDay(_ ymd: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: ymd) else { return ymd }
        let o = DateFormatter(); o.locale = Locale(identifier: "en_GB"); o.dateFormat = "EEE d MMM"
        return o.string(from: d)
    }

    /// Today's shift and the days that follow it without a gap.
    static func shiftRun(_ days: [String]) -> [String] {
        let set = Set(days)
        var out: [String] = []
        var d = Date()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        while set.contains(f.string(from: d)) { out.append(f.string(from: d)); d = d.addingTimeInterval(86400) }
        return out
    }

    // MARK: Linear reads

    struct BoardIssue: Decodable {
        struct State: Decodable { let name: String; let type: String }
        struct Named: Decodable { let name: String }
        struct Labels: Decodable { let nodes: [Named] }
        let identifier: String
        let title: String
        let url: String
        let priority: Double?
        let state: State
        let labels: Labels
        struct Ref: Decodable { let identifier: String; let title: String }
        let parent: Ref?
        struct Person: Decodable { let isMe: Bool? }
        let assignee: Person?
        var gated: Bool { labels.nodes.contains { $0.name == OnCall.gate } }
        /// Assigned to someone else: not his, not shown (18-nov).
        var others: Bool { assignee != nil && assignee?.isMe != true }
    }

    /// The open on-call board: team ES, label Eng Oncall, without Technical Support. Every page: on 18-nov it held 292
    /// open issues, and reading only the first 250 let issues of other people show in the review as if they were his.
    static func board(key: String) async throws -> [BoardIssue] {
        var out: [BoardIssue] = []
        var after: String? = nil
        for _ in 0..<10 {
            let cursor = after.map { ", after: \"\($0)\"" } ?? ""
            let query = """
            query { issues(first: 250\(cursor), filter: {
              team: { key: { eq: "\(team)" } }, labels: { name: { eq: "\(label)" } }, state: { type: { nin: ["completed", "canceled"] } }
            }) { nodes { identifier title url priority state { name type } labels { nodes { name } } parent { identifier title } assignee { isMe } }
                 pageInfo { hasNextPage endCursor } } }
            """
            let data = try await Linear.send(query, key: key)
            struct Page: Decodable { let hasNextPage: Bool; let endCursor: String? }
            struct Env: Decodable { struct D: Decodable { struct I: Decodable { let nodes: [BoardIssue]; let pageInfo: Page }; let issues: I }; let data: D?; let errors: [Linear.GQLError]? }
            let env = try JSONDecoder().decode(Env.self, from: data)
            if let e = env.errors?.first { throw QuicksaveError.message("Linear: \(e.message)") }
            guard let issues = env.data?.issues else { break }
            out += issues.nodes
            guard issues.pageInfo.hasNextPage, let next = issues.pageInfo.endCursor else { break }
            after = next
        }
        return out.filter { !$0.gated }
    }

    /// What he works: in Triage or not, as long as it is his or nobody's.
    static func mine(key: String) async throws -> [BoardIssue] {
        try await board(key: key).filter { !$0.others }
    }

    struct Quest {
        let identifier: String
        let title: String
        let url: URL?
        let description: String
        /// The cards it lists, in order, with their tag.
        var cards: [(id: String, tag: String)] { OnCall.cards(in: description) }
    }

    /// His open on-call Main Quest in TEMI, if any.
    static func quest(key: String) async throws -> Quest? {
        let query = """
        query { issues(first: 3, filter: {
          assignee: { isMe: { eq: true } }, team: { key: { eq: "TEMI" } }, title: { startsWith: "\(titlePrefix)" },
          state: { type: { nin: ["completed", "canceled"] } }
        }) { nodes { identifier title url description } } }
        """
        let data = try await Linear.send(query, key: key)
        struct N: Decodable { let identifier: String; let title: String; let url: String; let description: String? }
        struct Env: Decodable { struct D: Decodable { struct I: Decodable { let nodes: [N] }; let issues: I }; let data: D? }
        guard let n = try JSONDecoder().decode(Env.self, from: data).data?.issues.nodes.first else { return nil }
        return Quest(identifier: n.identifier, title: n.title, url: URL(string: n.url), description: n.description ?? "")
    }

    /// `1. [ES-123 (tag)](url): …` lines under `## Cards`.
    static func cards(in description: String) -> [(id: String, tag: String)] {
        var inCards = false
        var out: [(String, String)] = []
        let re = try! NSRegularExpression(pattern: #"\[([A-Z]+-\d+)\s*(?:\(([^)]*)\))?\]"#)
        for raw in description.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { inCards = line.lowercased().hasPrefix("## cards"); continue }
            guard inCards else { continue }
            let ns = line as NSString
            guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let id = ns.substring(with: m.range(at: 1))
            let tag = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
            if !out.contains(where: { $0.0 == id }) { out.append((id, tag)) }
        }
        return out
    }

    /// The on-call Main Quest's description: the summary line, then the cards with their priority and state.
    static func description(shift: [String], cards: [(id: String, tag: String)], issues: [LinearIssue], reviewed: Date) -> String {
        let t = DateFormatter(); t.dateFormat = "HH:mm"
        let byId = Dictionary(issues.map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })
        let open = cards.filter { byId[$0.id].map { !["completed", "canceled"].contains($0.state.type) } ?? true }
        func count(_ p: String) -> Int { open.filter { priorityName(byId[$0.id]?.priority) == p }.count }
        let rest = open.count - count("urgent") - count("high")
        let span = shift.isEmpty ? "" : "On-call shift, \(shortDay(shift.first!)) to \(shortDay(shift.last!)). "
        var lines = ["\(span)Last review \(t.string(from: reviewed)): \(count("urgent")) urgent, \(count("high")) high, \(rest) other open.",
                     "", "Written by Quicksave on every Apply. Each card's state lives in its own issue.", "", "## Cards"]
        for (i, c) in cards.enumerated() {
            let issue = byId[c.id]
            let url = issue?.url ?? "https://linear.app/alan-eu/issue/\(c.id)"
            let p = priorityName(issue?.priority).capitalized
            lines.append("\(i + 1). [\(c.id) (\(c.tag))](\(url)): \(p), \(issue?.state.name ?? "unknown").")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Writes

    /// The first "identifier" anywhere in Orca's answer.
    static func identifier(in data: Data) -> String? {
        func walk(_ v: Any) -> String? {
            if let d = v as? [String: Any] {
                if let p = d["identifier"] as? String, p.contains("-") { return p }
                for (_, x) in d { if let p = walk(x) { return p } }
            } else if let a = v as? [Any] { for x in a { if let p = walk(x) { return p } } }
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)).flatMap(walk)
    }

    static func bodyFile(_ text: String) throws -> URL {
        let file = URL(fileURLWithPath: Morning.scratch).appendingPathComponent("oncall-\(UUID().uuidString).md")
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Creates an issue through Orca and returns its code.
    static func create(_ args: [String], body: String) async throws -> String {
        let file = try bodyFile(body)
        defer { try? FileManager.default.removeItem(at: file) }
        let r = try await Shell.run(Orca.binary, ["linear", "create"] + args + ["--body-file", file.path, "--json"])
        if let id = identifier(in: r.out) { return id }
        let said = String(data: r.err.isEmpty ? r.out : r.err, encoding: .utf8) ?? ""
        throw QuicksaveError.message("Linear did not create the issue: \(said.prefix(300))")
    }

    // MARK: Worktrees

    /// The shift's parent worktree in alan-apps, created on the first Apply of the shift.
    static func parentWorktree(shift: [String]) async throws -> String {
        let name = parentPrefix + " " + shortDay(shift.first ?? Morning.today)
        if let w = await Orca.worktree(named: name), FileManager.default.fileExists(atPath: w.path) { return w.path }
        let created = try await Orca.run(["worktree", "create", "--repo", "name:alan-apps", "--name", name, "--no-parent",
                                          "--comment", "Parent of this on-call shift's worktrees, one per card. Opened by Quicksave.",
                                          "--setup", "skip", "--json"])
        guard let path = Reviews.findPathPublic(in: created) else { throw QuicksaveError.message("Orca did not say where the on-call parent worktree is.") }
        return path
    }

    /// One worktree per card, under the shift's parent, linked to its issue so the card finds it.
    static func cardWorktree(_ id: String, tag: String, parent: String) async throws -> String {
        if let m = await Orca.worktree(for: id), let w = await Orca.worktree(named: m.name), FileManager.default.fileExists(atPath: w.path) {
            return w.path
        }
        let created = try await Orca.run(["worktree", "create", "--repo", "name:alan-apps", "--name", "\(id) \(tag)",
                                          "--parent-worktree", "path:\(parent)", "--linear-issue", id,
                                          "--comment", "On-call: \(id) (\(tag)), investigation started by Quicksave",
                                          "--setup", "inherit", "--json"])
        guard let path = Reviews.findPathPublic(in: created) else { throw QuicksaveError.message("Orca did not say where \(id)'s worktree is.") }
        return path
    }

    /// The first prompt of a card's agent, on one line: Orca types it into the terminal.
    static func kickoff(id: String, title: String, url: String, slack: String?) -> String {
        [
            "On-call: work \(id) — \(title) (\(url)).\(slack.map { " It came from this Slack thread: \($0)." } ?? "")",
            title.hasPrefix("Children of ") ? "\(id) is a group: work its open children on the on-call board (team ES, label Eng Oncall) together. Look first for the cause they share, fix that once, and say which children it closes." : "",
            "Run the alan-spain:oncall skill and go straight to its investigate-issue phase for this issue, in this worktree.",
            "Skip every task-tracking step that writes to the vault: Quicksave and Linear track this issue.",
            "Alejandro asked for more than the skill, and this overrides its never-commit rule in this worktree only:",
            "(1) When you find a fix, make it here and run the tests that cover it. Then commit on this worktree's branch, push the branch and open a DRAFT pull request with gh pr create --draft: English title starting with \(id), body with problem, root cause, fix and how it was tested. Never mark it ready, never merge, never ask for reviewers.",
            "(2) Never post anything: no Linear comment, no Slack message, no GitHub comment. Every text he must post is a draft: write it as a JSON file in \"\(draftsFolder)/\" named \(id)-<n>.json with the keys where (Linear, Slack or GitHub), note (one line: where and when to post it), link (the issue or Slack thread URL) and text. Before writing one, read \"\(draftsFolder)/open/\(id).json\" if it exists: the drafts for this issue still open in Quicksave, each with its id. If yours is a new version of one of them, add the key replaces with that id; if it is a different message, set replaces to \"new\". Without replaces, it replaces the newest open draft for this issue in the same place. At least the Linear comment with the root cause and the fix, and the Slack reply when the issue came from Slack. Quicksave moves them into its Drafts.",
            "(3) Progress goes to the Orca worktree comment.",
            "(4) If there is nothing to fix in code (a data fix, config, a question), say so, write the drafts and stop.",
            "Spanish to me, English for anything outbound, no em-dashes.",
        ].joined(separator: " ")
    }

    /// Moves the drafts the card agents left into Drafts, linked to their card.
    static func importDrafts() -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: draftsFolder) else { return 0 }
        struct D: Decodable {
            let place: String?; let note: String?; let link: String?; let text: String
            /// The id of the open draft this one is a new version of, or "new" for a different message.
            let replaces: Database.DraftReplace
            enum CodingKeys: String, CodingKey { case place = "where", note, link, text, replaces }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                place = try c.decodeIfPresent(String.self, forKey: .place)
                note = try c.decodeIfPresent(String.self, forKey: .note)
                link = try c.decodeIfPresent(String.self, forKey: .link)
                text = try c.decode(String.self, forKey: .text)
                if let id = (try? c.decodeIfPresent(Int64.self, forKey: .replaces)) ?? nil { replaces = .draft(id) }
                else if let s = (try? c.decodeIfPresent(String.self, forKey: .replaces)) ?? nil {
                    replaces = s.lowercased() == "new" ? .new : Int64(s).map { .draft($0) } ?? .auto
                } else { replaces = .auto }
            }
        }
        var n = 0
        for f in files where f.hasSuffix(".json") {
            let path = draftsFolder + "/" + f
            guard let data = fm.contents(atPath: path) else { continue }
            let item = f.range(of: #"^[A-Z]+-\d+"#, options: .regularExpression).map { String(f[$0]) }
            let list: [D] = (try? JSONDecoder().decode([D].self, from: data)) ?? ((try? JSONDecoder().decode(D.self, from: data)).map { [$0] } ?? [])
            guard !list.isEmpty else { continue }
            let drafts = list.map { d -> Database.NewDraft in
                let place = ["Linear", "Slack", "GitHub", "Mail"].contains(d.place ?? "") ? d.place! : "Other"
                let text = place == "Slack" ? SlackDraftText.normalized(d.text) : d.text
                return Database.NewDraft(place: place, note: d.note ?? "On-call", link: d.link, body: text, source: "on-call",
                                         item: item, replaces: d.replaces)
            }
            Database.shared.addDrafts(drafts)
            n += drafts.count
            try? fm.moveItem(atPath: path, toPath: draftsFolder + "/imported/" + "\(Int(Date().timeIntervalSince1970))-" + f)
        }
        return n
    }

    /// Leaves each card's open drafts where its agent can read them, so a rewrite says which one it replaces.
    static func exportOpenDrafts(_ drafts: [DraftItem]) {
        let folder = draftsFolder + "/open"
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let old = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        let byItem = Dictionary(grouping: drafts.filter { !$0.item.isEmpty }, by: \.item)
        for f in old where f.hasSuffix(".json") && byItem[String(f.dropLast(5))] == nil {
            try? FileManager.default.removeItem(atPath: folder + "/" + f)
        }
        for (item, list) in byItem {
            let rows: [[String: Any]] = list.map { ["id": $0.id, "where": $0.place, "note": $0.note, "text": $0.body] }
            guard let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted]) else { continue }
            let path = folder + "/\(item).json"
            if FileManager.default.contents(atPath: path) != data { FileManager.default.createFile(atPath: path, contents: data) }
        }
    }
}

extension Reviews {
    static func findPathPublic(in data: Data) -> String? {
        func walk(_ v: Any) -> String? {
            if let d = v as? [String: Any] {
                if let p = d["path"] as? String, p.hasPrefix("/") { return p }
                for (_, x) in d { if let p = walk(x) { return p } }
            } else if let a = v as? [Any] { for x in a { if let p = walk(x) { return p } } }
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)).flatMap(walk)
    }
}

// MARK: Agents

extension AgentJob {
    static let onCallReads = ["Read", "Grep", "Glob", "ToolSearch", "Bash(date:*)",
                              "mcp__claude_ai_Linear__list_issue_labels", "mcp__claude_ai_Linear__list_issue_statuses",
                              "mcp__claude_ai_Slack__slack_search_public_and_private", "mcp__claude_ai_Slack__slack_search_public",
                              "mcp__claude_ai_Slack__slack_read_thread", "mcp__claude_ai_Slack__slack_read_channel",
                              "mcp__claude_ai_Slack__slack_search_channels", "mcp__claude_ai_Slack__slack_search_users",
                              "mcp__claude_ai_Notion__notion-search", "mcp__claude_ai_Notion__notion-fetch",
                              "Bash(orca linear team labels:*)", "Bash(orca linear team states:*)"] + Morning.readLinear
    static let onCallNever = Morning.neverPost + ["Edit", "Write", "NotebookEdit", "mcp__claude_ai_Linear__save_issue",
                                                  "mcp__claude_ai_Slack__slack_send_message_draft", "Bash(orca linear save-issue:*)",
                                                  "Bash(orca linear status:*)", "Bash(orca linear priority:*)", "Bash(orca linear create:*)",
                                                  "Bash(git push:*)", "Bash(gh:*)"]

    static let onCallCardSchema = """
    {"type":"object","properties":{"issue":{"type":"string"},"title":{"type":"string"},"tag":{"type":"string"},"url":{"type":"string"},"source":{"type":"string","enum":["Linear","Slack"]},"slackLink":{"type":"string"},"currentPriority":{"type":"string","enum":["urgent","high","medium","low","none"]},"currentState":{"type":"string"},"priority":{"type":"string","enum":["urgent","high","medium","low","none"]},"state":{"type":"string"},"parent":{"type":"string"},"currentParent":{"type":"string"},"typeLabel":{"type":"string"},"assignToMe":{"type":"boolean"},"enters":{"type":"boolean"},"why":{"type":"string"}},"required":["title","tag","source","currentPriority","currentState","priority","state","assignToMe","enters","why"]}
    """

    static let onCallCardRules = """
    Each card:
    - issue: its code (ES-123), or empty for a Slack call that has no issue yet. title, url, tag (2-3 words saying what it is), source (Linear or Slack), slackLink (the Slack message, when a call is behind it).
    - currentPriority and currentState: as Linear has them now (none and empty for a Slack call).
    - priority (urgent, high, medium, low, none) and state (the exact Linear state name it should be in; the current one to leave it).
    - currentParent: the code of the parent it has now in Linear, or empty.
    - parent: the ES code of its parent problem, only from the real list and only when it has none; empty otherwise. typeLabel: the exact type label to add, or empty when it already has one. assignToMe: true when it should be his and is not.
    - enters: true when he should work it today. Every urgent and every high enter; others only when they are quick or close to breaching their SLA.
    - why: one short line on the proposal, naming any SLA risk.
    English, short, no em-dashes.
    """

    /// Reads the on-call board and the Slack calls and proposes what to do with each. It changes nothing.
    static func onCallReview(since: Date, onBoard: [(id: String, tag: String)], previous: OnCallReview?) -> AgentJob {
        let iso = ISO8601DateFormatter().string(from: since)
        let skill = OnCall.skill
        let prev: String = {
            guard let p = previous else { return "" }
            let lines = p.items.map { "- \($0.issue ?? $0.slackLink ?? $0.title): \($0.priority), \($0.state), \($0.enters ? "entered" : "left out")\($0.applied != nil ? ", applied" : "")" }
            return "The previous review (\(ISO8601DateFormatter().string(from: p.created))) proposed, and he decided:\n" + lines.joined(separator: "\n")
        }()
        return AgentJob(
            name: "on-call review",
            directory: NSHomeDirectory() + "/vault",
            prompt: """
            You prepare Alejandro's on-call review for Spain Eng. He is the on-call engineer today, \(Morning.todayLong). Quicksave started you when he pressed Review on-call. He reads your proposal in the app, corrects it and applies it himself. You change nothing anywhere: no Linear writes, no messages.

            Read \(skill)/SKILL.md and \(skill)/references/triage.md. Follow triage steps 1 to 4 (fetch, parent problems, types, the proposal) with these differences:
            - Look at the whole open board, not only Triage: team ES, label Eng Oncall, every state except Done and Canceled. Drop archived issues, those still labelled Technical Support, and those assigned to someone other than him: he only wants his own and unassigned ones. assignToMe is true only for unassigned ones.
            - Slack: find every message since \(iso) that calls the on-call handles. @spain_eng_oncall: every call counts, never skip one. @eng_oncall: only when the message is clearly for Spain Eng (Spanish members, the Spanish product, a Spain team); most are not for us. Search for the handles' mentions with the Slack search tools, and look at #area_spain and #eng_spain_alerts. A call that already has its Linear issue goes on that issue's card, never on a card of its own.
            - Cards already on his on-call board today: \(onBoard.isEmpty ? "none" : onBoard.map { "\($0.id) (\($0.tag))" }.joined(separator: ", ")).
            \(previous == nil ? "- This is the first review of the shift: one card for every open issue and every call." : "- Propose only what changed since the previous review: new issues, new Slack calls, priorities or states someone else changed, cards on his board that closed or should leave. Leave out what he already decided and did not change.\n\n" + prev)

            \(onCallCardRules)

            summary: two or three sentences for him: what is on fire, what enters today, anything odd (owner anomalies, SLA breaches, bulk auto-generated issues).

            \(Morning.howToRun)
            - Notion tools are deferred too.
            """,
            model: "claude-opus-5-5",
            allowed: onCallReads,
            denied: onCallNever,
            schema: """
            {"type":"object","properties":{"cards":{"type":"array","items":\(onCallCardSchema)},"summary":{"type":"string"}},"required":["cards","summary"]}
            """,
            maxTurns: 120,
            extraDirectories: [skill])
    }

    /// His message about the review, with the corrections he wrote on the cards. It continues the review's session.
    static func onCallTalk(_ review: OnCallReview, message: String) -> AgentJob {
        struct Card: Encodable {
            let id: String; let issue: String?; let title: String; let tag: String; let priority: String; let state: String
            let parent: String?; let typeLabel: String?; let assignToMe: Bool; let enters: Bool; let why: String; let correction: String
        }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let cards = review.items.filter { $0.open }.map {
            Card(id: $0.id, issue: $0.issue, title: $0.title, tag: $0.tag, priority: $0.priority, state: $0.state, parent: $0.parent,
                 typeLabel: $0.typeLabel, assignToMe: $0.assignToMe, enters: $0.enters, why: $0.why, correction: $0.correction)
        }
        let json = (try? enc.encode(cards)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return AgentJob(
            name: "on-call talk",
            directory: NSHomeDirectory() + "/vault",
            prompt: """
            Alejandro is going through the on-call review you prepared in this session, in Quicksave, and talks to you about it. He often dictates, so expect loose wording.

            His message:
            <<<
            \(message)
            >>>

            The cards as they are now. He may have changed priority or enters by hand: his hand changes win. `correction` is what he wrote on a card: apply it to that card.
            \(json)

            Answer him in `answer`, in the language he wrote in, short, in Markdown. When what he says or a correction asks for a change, make it and say what changed. Read Linear or Slack again when you need to.

            Return every card above in `cards`, changed or not, with its `id` as given. A card he wants gone: leave it out. A new card he asks for: add it with an empty id.
            \(onCallCardRules)
            summary: the review's summary, updated. changed: one sentence on what you changed, or "Nothing changed."

            \(Morning.howToRun)
            """,
            model: "claude-opus-5-5",
            allowed: onCallReads,
            denied: onCallNever,
            schema: """
            {"type":"object","properties":{"cards":{"type":"array","items":\(onCallCardSchema.replacingOccurrences(of: "{\"issue\"", with: "{\"id\":{\"type\":\"string\"},\"issue\""))},"summary":{"type":"string"},"answer":{"type":"string"},"changed":{"type":"string"}},"required":["cards","summary","answer","changed"]}
            """,
            maxTurns: 60,
            resume: review.session)
    }

    /// Looks for calls to the on-call handles in Slack since a moment. Reads only.
    static func onCallSlack(since: Date) -> AgentJob {
        AgentJob(
            name: "on-call slack",
            directory: NSTemporaryDirectory(),
            prompt: """
            Find every Slack message since \(ISO8601DateFormatter().string(from: since)) that calls the Spain Eng on-call. Today is \(Morning.todayLong).
            - @spain_eng_oncall: every message that mentions it counts. Never skip one.
            - @eng_oncall: only messages clearly for Spain Eng (Spanish members, the Spanish product, a Spain team). Most are not: leave those out.
            Search the handles' mentions with the Slack search tools (try the handle text with and without @), and read #area_spain and #eng_spain_alerts since that moment. The Slack tools are deferred: find them first with ToolSearch.
            For each call: when (ISO 8601), handle (spain_eng_oncall or eng_oncall), author, channel, text (the message, at most 300 characters), link (its Slack URL), issue (an ES code if the message or its thread names one, else empty), urgent (true when it reads as production broken, members blocked, data or money at risk).
            Read only: never send, draft or react.
            """,
            model: "claude-sonnet-5-5",
            allowed: ["ToolSearch", "mcp__claude_ai_Slack__slack_search_public_and_private", "mcp__claude_ai_Slack__slack_search_public",
                      "mcp__claude_ai_Slack__slack_read_thread", "mcp__claude_ai_Slack__slack_read_channel",
                      "mcp__claude_ai_Slack__slack_search_channels", "mcp__claude_ai_Slack__slack_search_users"],
            denied: Morning.neverPost + ["mcp__claude_ai_Slack__slack_send_message_draft"],
            schema: """
            {"type":"object","properties":{"calls":{"type":"array","items":{"type":"object","properties":{"when":{"type":"string"},"handle":{"type":"string"},"author":{"type":"string"},"channel":{"type":"string"},"text":{"type":"string"},"link":{"type":"string"},"issue":{"type":"string"},"urgent":{"type":"boolean"}},"required":["when","handle","author","channel","text","link","urgent"]}}},"required":["calls"]}
            """,
            maxTurns: 30)
    }

    /// His on-call shift days from Alan Home.
    static func onCallShift() -> AgentJob {
        AgentJob(
            name: "on-call shift",
            directory: NSTemporaryDirectory(),
            prompt: """
            Find Alejandro's on-call shift days. Call get_authenticated_alaner for his id, then list_alaner_next_oncall_shifts with it. The Alan Home tools are deferred: find them first with ToolSearch (select:mcp__hopper-alan-home__get_authenticated_alaner,mcp__hopper-alan-home__list_alaner_next_oncall_shifts).
            Return days: every shift date it lists, as yyyy-MM-dd. Return an empty list when there are none.
            """,
            model: "claude-haiku-5-5",
            allowed: ["ToolSearch", "mcp__hopper-alan-home__get_authenticated_alaner", "mcp__hopper-alan-home__list_alaner_next_oncall_shifts"],
            denied: Morning.neverPost,
            schema: """
            {"type":"object","properties":{"days":{"type":"array","items":{"type":"string"}}},"required":["days"]}
            """,
            maxTurns: 8,
            settingSources: "user,project,local")
    }
}

struct OnCallCardOut: Decodable {
    let id: String?
    let issue: String?
    let title: String
    let tag: String
    let url: String?
    let source: String
    let slackLink: String?
    let currentPriority: String
    let currentState: String
    let priority: String
    let state: String
    let parent: String?
    let currentParent: String?
    let typeLabel: String?
    let assignToMe: Bool
    let enters: Bool
    let why: String

    func proposal(id given: String? = nil) -> OnCallProposal {
        let code = (issue ?? "").isEmpty ? nil : issue
        func clean(_ s: String?) -> String? { (s ?? "").isEmpty ? nil : s }
        return OnCallProposal(id: given ?? code ?? "slack:" + (slackLink ?? UUID().uuidString), issue: code, title: title, tag: tag,
                              url: clean(url), source: source, slackLink: clean(slackLink), currentPriority: currentPriority,
                              currentState: currentState, priority: priority, state: state, parent: clean(parent),
                              currentParent: clean(currentParent), typeLabel: clean(typeLabel), assignToMe: assignToMe, enters: enters, why: why)
    }
}

struct OnCallReviewResult: Decodable { let cards: [OnCallCardOut]; let summary: String }
struct OnCallTalkResult: Decodable { let cards: [OnCallCardOut]; let summary: String; let answer: String; let changed: String }
struct OnCallSlackResult: Decodable {
    struct Call: Decodable { let when: String; let handle: String; let author: String; let channel: String; let text: String; let link: String; let issue: String?; let urgent: Bool }
    let calls: [Call]
}
struct OnCallShiftResult: Decodable { let days: [String] }

// MARK: Store

extension Store {
    var onShiftToday: Bool { onCall.shiftDays.contains(Morning.today) || ProcessInfo.processInfo.environment["QUICKSAVE_ONCALL"] == "1" }
    /// The tab shows while he is on shift, and while a review of today is still open.
    var showOnCall: Bool { onShiftToday || onCallQuest != nil || (onCall.review.map { Calendar.current.isDateInToday($0.created) } ?? false) }

    func editOnCall(_ change: (inout OnCallState) -> Void) {
        change(&onCall)
        OnCall.save(onCall)
    }

    /// Cards of issues assigned to someone else leave the review for good: he wants to know nothing of them.
    func discardOthers() {
        guard let items = onCall.review?.items,
              items.contains(where: { $0.open && ($0.issue.map { onCallOthers.contains($0) } ?? false) }) else { return }
        editOnCall { s in
            guard var items = s.review?.items else { return }
            for i in items.indices where items[i].open && (items[i].issue.map { onCallOthers.contains($0) } ?? false) {
                items[i].discarded = Date()
            }
            s.review?.items = items
        }
    }

    /// He groups every child of a parent into one card, or undoes it.
    func setGroup(_ parent: String, name: String?) {
        editOnCall { s in if let name { s.groups[parent] = name } else { s.groups[parent] = nil } }
    }

    /// Changes every pending card of a group at once.
    func editGroup(_ parent: String, _ change: (inout OnCallProposal) -> Void) {
        editOnCall { s in
            guard var items = s.review?.items else { return }
            for i in items.indices where items[i].currentParent == parent && items[i].open { change(&items[i]) }
            s.review?.items = items
        }
    }

    func editProposal(_ id: String, _ change: (inout OnCallProposal) -> Void) {
        editOnCall { s in
            guard let i = s.review?.items.firstIndex(where: { $0.id == id }) else { return }
            change(&s.review!.items[i])
        }
    }

    /// Every refresh: the shift (once a day), the on-call Main Quest and its cards, new urgent issues, the agents' drafts.
    func refreshOnCall(key: String) async {
        if onCall.shiftChecked != Morning.today, !onCallShiftLoading {
            onCallShiftLoading = true
            Task { @MainActor in
                defer { onCallShiftLoading = false }
                guard let run = try? await Agents.run(.onCallShift()),
                      let r = try? JSONDecoder().decode(OnCallShiftResult.self, from: Data(run.resultJSON.utf8)) else { return }
                editOnCall { $0.shiftDays = r.days; $0.shiftChecked = Morning.today }
                await refresh()
            }
        }
        if OnCall.importDrafts() > 0 { loadDrafts() }
        OnCall.exportOpenDrafts(drafts)
        let parents = Set((onCall.review?.items ?? []).compactMap(\.currentParent) + onCall.groups.keys).subtracting(onCall.parentTitles.keys)
        if !parents.isEmpty, let found = try? await Linear.issues(key: key, ids: parents.sorted()) {
            editOnCall { s in for i in found { s.parentTitles[i.identifier] = i.title } }
        }
        do {
            let q = try await OnCall.quest(key: key)
            onCallQuest = q
            let cards = q?.cards ?? []
            let issues = try await Linear.pieces(key: key, ids: cards.map(\.id))
            onCallCards = cards.enumerated().compactMap { i, c in
                issues.first { $0.identifier == c.id }.map { iss in
                    var p = Piece.from(iss, order: i + 1, tag: c.tag, step: "", isSide: true)
                    p.onCall = true
                    p.priority = OnCall.priorityName(iss.priority)
                    return p
                }
            }
            for p in onCallCards { if let m = await Orca.worktree(for: p.id) { worktrees[p.id] = m } }
            for pr in onCallCards.flatMap(\.pullRequests) { if let st = await GitHub.status(of: pr) { prStatus[pr.number] = st } }
            // The shift is over: its Main Quest closes as Done.
            if let q, !onCall.shiftDays.isEmpty, onCall.shiftChecked == Morning.today, !onShiftToday {
                try? await Orca.linearWrite(["status", "set", q.identifier, "--to", "Done"])
                onCallQuest = nil
                onCallCards = []
            }
        } catch {
            onCallNotice = "The on-call board could not be read: \(error.localizedDescription)"
        }
        guard onShiftToday else { return }
        await watchUrgent(key: key)
        if Date().timeIntervalSince(onCallSlackLooked ?? .distantPast) > 900 { watchSlack() }
    }

    /// A new urgent issue on the on-call board is told at once on Telegram, without waiting for a review.
    private func watchUrgent(key: String) async {
        guard let everything = try? await OnCall.board(key: key) else { return }
        let others = Set(everything.filter(\.others).map(\.identifier))
        if others != onCallOthers { onCallOthers = others }
        discardOthers()
        let board = everything.filter { !$0.others }
        let entered = Set(onCallCards.map(\.id))
        let all = board.filter { OnCall.priorityName($0.priority) == "urgent" && !entered.contains($0.identifier) && !onCall.notified.contains($0.identifier) }
        // A grouped parent is told once a day, however many children arrive.
        let grouped = Dictionary(grouping: all.filter { $0.parent.map { onCall.groups[$0.identifier] != nil } ?? false }, by: { $0.parent!.identifier })
        let fresh = all.filter { i in !(i.parent.map { onCall.groups[$0.identifier] != nil } ?? false) }
        let groupsToTell = grouped.filter { onCall.groupNotified[$0.key] != Morning.today }
        if !groupsToTell.isEmpty {
            await Notify.send("🚨 New urgent in grouped alerts:\n" + groupsToTell.map { "\($0.key) (\(onCall.groups[$0.key] ?? "")): \($0.value.count) urgent" }.joined(separator: "\n"))
            editOnCall { s in for k in groupsToTell.keys { s.groupNotified[k] = Morning.today } }
        }
        if !grouped.isEmpty { editOnCall { $0.notified += grouped.values.flatMap { $0.map(\.identifier) } } }
        // One message for the lot: the first look of a shift found 21 at once and sent 21 messages (18-nov).
        if fresh.count == 1, let i = fresh.first {
            await Notify.send("🚨 Urgent on-call: \(i.identifier) \(i.title) (\(i.state.name))\n\(i.url)")
        } else if !fresh.isEmpty {
            await Notify.send("🚨 \(fresh.count) urgent on-call issues not on your board:\n" + fresh.prefix(12).map { "\($0.identifier) \($0.title)" }.joined(separator: "\n")
                              + (fresh.count > 12 ? "\nand \(fresh.count - 12) more" : ""))
        }
        if !fresh.isEmpty { editOnCall { $0.notified += fresh.map(\.identifier) } }
    }

    /// Calls to the on-call handles in Slack, every 15 minutes during the shift. Every call to @spain_eng_oncall is told.
    private func watchSlack() {
        onCallSlackLooked = Date()
        let since = onCall.slackSince ?? Calendar.current.startOfDay(for: Date())
        let started = Date()
        Task { @MainActor in
            guard let run = try? await Agents.run(.onCallSlack(since: since)),
                  let r = try? JSONDecoder().decode(OnCallSlackResult.self, from: Data(run.resultJSON.utf8)) else { return }
            let known = Set(onCall.slackCalls.map(\.id))
            let calls = r.calls.map { OnCallSlackCall(when: $0.when, handle: $0.handle, author: $0.author, channel: $0.channel,
                                                       text: $0.text, link: $0.link, issue: ($0.issue ?? "").isEmpty ? nil : $0.issue) }
            let new = calls.filter { !known.contains($0.id) }
            let told = zip(calls, r.calls).filter { !known.contains($0.0.id) }
            if told.count == 1, let (c, raw) = told.first {
                await Notify.send("\(raw.urgent ? "🚨" : "📣") @\(c.handle) in #\(c.channel) by \(c.author): \(c.text.prefix(200))\n\(c.link)")
            } else if !told.isEmpty {
                await Notify.send("📣 \(told.count) calls to the on-call in Slack:\n" + told.prefix(8).map { c, raw in
                    "\(raw.urgent ? "🚨 " : "")@\(c.handle) #\(c.channel): \(c.text.prefix(120))" }.joined(separator: "\n"))
            }
            editOnCall { s in
                s.slackSince = started
                s.slackCalls = (s.slackCalls + new).filter { QSDate.parse($0.when).map { Calendar.current.isDateInToday($0) } ?? true }
                s.seenCalls = s.seenCalls.filter { id in s.slackCalls.contains { $0.id == id } }
            }
        }
    }

    /// A new review replaces the current one, chat included. While he is talking to the agent about a review he has
    /// not applied yet, that would throw away what he asked (18-nov), so Review waits for Apply.
    var onCallReviewLocked: Bool {
        guard let r = onCall.review else { return false }
        return !r.chat.isEmpty && r.items.contains { $0.open }
    }

    /// Review on-call: the agent reads the board and Slack and proposes a card for each item. Nothing is written.
    func reviewOnCall() async {
        guard !onCallBusy, !onCallReviewLocked else { return }
        onCallBusy = true
        onCallNotice = nil
        onCallStep = "Starting"
        defer { onCallBusy = false; onCallStep = nil }
        let previous = onCall.review.flatMap { Calendar.current.isDateInToday($0.created) ? $0 : nil }
        let since = onCall.lastReview.flatMap { Calendar.current.isDateInToday($0) ? $0 : nil }
            ?? Calendar.current.startOfDay(for: Date()).addingTimeInterval(-15 * 3600)
        do {
            let run = try await Agents.run(.onCallReview(since: since, onBoard: onCallQuest?.cards ?? [], previous: previous)) { step in
                Task { @MainActor [weak self] in self?.onCallStep = step }
            }
            guard let r = try? JSONDecoder().decode(OnCallReviewResult.self, from: Data(run.resultJSON.utf8)) else {
                throw QuicksaveError.message("The agent's result could not be read: \(run.resultJSON.prefix(300))")
            }
            var seen = Set<String>()
            let items = r.cards.map { $0.proposal() }.filter { seen.insert($0.id).inserted }
            editOnCall { s in
                s.review = OnCallReview(items: items, summary: r.summary, session: run.sessionId, cost: run.cost)
                s.lastReview = Date()
            }
            if let key = Database.shared.secret("linearApiKey"), let all = try? await OnCall.board(key: key) {
                onCallOthers = Set(all.filter(\.others).map(\.identifier))
            }
            discardOthers()
            await refresh()
        } catch {
            onCallNotice = "The review could not be made: \(error.localizedDescription)"
        }
    }

    /// He talks to the review's agent, which applies what he says and the corrections on the cards.
    func talkOnCall(_ message: String) async {
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty, !onCallBusy, var review = onCall.review else { return }
        onCallBusy = true
        onCallNotice = nil
        onCallStep = "Starting"
        defer { onCallBusy = false; onCallStep = nil }
        func nextId(_ r: OnCallReview) -> Int64 { (r.chat.map(\.id).max() ?? 0) + 1 }
        review.chat.append(ReviewChatTurn(id: nextId(review), mine: true, text: msg))
        editOnCall { $0.review?.chat = review.chat }
        do {
            let run = try await Agents.run(.onCallTalk(review, message: msg)) { step in
                Task { @MainActor [weak self] in self?.onCallStep = step }
            }
            guard let r = try? JSONDecoder().decode(OnCallTalkResult.self, from: Data(run.resultJSON.utf8)) else {
                throw QuicksaveError.message("The agent's result could not be read.")
            }
            editOnCall { s in
                guard var rv = s.review else { return }
                let applied = rv.items.filter { !$0.open }
                let before = Dictionary(rv.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                var out = applied
                for c in r.cards {
                    let given = (c.id ?? "").isEmpty ? nil : c.id
                    var p = c.proposal(id: given)
                    if let old = given.flatMap({ before[$0] }) {
                        p.touched = p.priority != old.priority || p.state != old.state || p.enters != old.enters || p.why != old.why
                    } else { p.touched = true }
                    if !out.contains(where: { $0.id == p.id }) { out.append(p) }
                }
                rv.items = out
                rv.summary = r.summary
                let changed = r.changed.lowercased().hasPrefix("nothing") ? nil : r.changed
                rv.chat.append(ReviewChatTurn(id: nextId(rv), mine: false, text: r.answer, changed: changed))
                if let sid = run.sessionId { rv.session = sid }
                s.review = rv
            }
        } catch {
            onCallNotice = error.localizedDescription
        }
    }

    /// Apply: writes what he kept to Linear and puts the entering cards on the on-call Main Quest. Agents start only
    /// from Start on a card.
    func applyOnCall() async {
        guard !onCallBusy, let review = onCall.review, let key = Database.shared.secret("linearApiKey") else { return }
        onCallBusy = true
        onCallNotice = nil
        defer { onCallBusy = false; onCallStep = nil }
        var entering: [(id: String, tag: String, title: String, url: String, slack: String?)] = []
        var problems: [String] = []
        // Cards assigned to someone else are hidden, and never applied.
        for item in review.items where item.open && !(item.issue.map { onCallOthers.contains($0) } ?? false) {
            onCallStep = "Writing \(item.issue ?? item.tag)"
            var errors: [String] = []
            var code = item.issue
            if code == nil {
                guard item.enters else { editProposal(item.id) { $0.applied = Date() }; continue }
                do {
                    let body = "From Slack: \(item.slackLink ?? "no link")\n\n\(item.why)\n\nOpened by Quicksave from an on-call call."
                    code = try await OnCall.create(["--title", item.title, "--team", OnCall.team, "--label", OnCall.label,
                                                    "--priority", item.priority, "--state", item.state.isEmpty ? "Todo" : item.state,
                                                    "--assignee", "me"], body: body)
                } catch { errors.append(error.localizedDescription) }
            } else {
                let id = code!
                func w(_ args: [String]) async { do { try await Orca.linearWrite(args) } catch { errors.append(error.localizedDescription) } }
                if item.priority != item.currentPriority { await w(["priority", "set", id, "--to", item.priority]) }
                if !item.state.isEmpty, item.state != item.currentState { await w(["status", "set", id, "--to", item.state]) }
                if item.assignToMe { await w(["assignee", "set", id, "--me"]) }
                if let l = item.typeLabel { await w(["label", "add", id, "--label", l]) }
                if let p = item.parent { await w(["save-issue", id, "--parent-id", p]) }
            }
            let err = errors.isEmpty ? nil : errors.joined(separator: " ")
            if let err { problems.append("\(item.issue ?? item.tag): \(err)") }
            editProposal(item.id) { $0.applied = Date(); $0.applyError = err; if let code { $0.issue = code } }
        }

        // What enters is every applied card of the review that enters, not only those of this pass: a pass cut half
        // way (18-nov) had written them, and the next pass created an empty Main Quest with no agents.
        for item in onCall.review?.items ?? [] where item.enters && item.applied != nil {
            guard let code = item.issue, !onCallOthers.contains(code) else { continue }
            if let g = item.currentParent, let name = onCall.groups[g] {
                // A grouped child enters as its parent: one card and one agent for the whole group.
                if !entering.contains(where: { $0.id == g }) {
                    entering.append((g, name, "Children of \(g) (\(name)) on the on-call board, worked together",
                                     "https://linear.app/alan-eu/issue/\(g)", nil))
                }
            } else if !entering.contains(where: { $0.id == code }) {
                entering.append((code, item.tag, item.title, item.url ?? "https://linear.app/alan-eu/issue/\(code)", item.slackLink))
            }
        }

        // The on-call Main Quest: created on the first Apply of the shift, its description rewritten every time.
        onCallStep = "Writing the on-call Main Quest"
        let shift = OnCall.shiftRun(onCall.shiftDays)
        do {
            var quest = try await OnCall.quest(key: key)
            var cards = quest?.cards ?? []
            for e in entering where !cards.contains(where: { $0.id == e.id }) { cards.append((e.id, e.tag)) }
            let issues = try await Linear.pieces(key: key, ids: cards.map(\.id))
            let ordered = cards.sorted { a, b in
                func rank(_ id: String) -> Int { let p = Int(issues.first { $0.identifier == id }?.priority ?? 0); return p == 0 ? 9 : p }
                return rank(a.id) < rank(b.id)
            }
            let body = OnCall.description(shift: shift, cards: ordered, issues: issues, reviewed: Date())
            if quest == nil {
                let title = "\(OnCall.titlePrefix) \(OnCall.shortDay(shift.first ?? Morning.today)) to \(OnCall.shortDay(shift.last ?? Morning.today))"
                let id = try await OnCall.create(["--title", title, "--team", "TEMI", "--assignee", "me", "--state", "In Progress",
                                                  "--due-date", shift.last ?? Morning.today], body: body)
                quest = OnCall.Quest(identifier: id, title: title, url: nil, description: body)
            } else if let q = quest {
                let file = try OnCall.bodyFile(body)
                defer { try? FileManager.default.removeItem(at: file) }
                try await Orca.linearWrite(["save-issue", q.identifier, "--body-file", file.path])
            }
            if let q = quest {
                for c in ordered where !(onCallQuest?.cards.contains { $0.id == c.id } ?? false) {
                    try? await Orca.linearWrite(["relation", "add", q.identifier, "--related", c.id, "--type", "related"])
                }
            }
        } catch {
            problems.append("On-call Main Quest: \(error.localizedDescription)")
        }

        // No worktree or agent here: Start on a card opens them with the on-call rules, when he chooses (18-nov).
        editOnCall { $0.review?.appliedAt = Date() }
        if !problems.isEmpty { onCallNotice = "Some of it did not go through: " + problems.joined(separator: " · ") }
        await refresh()
    }

    /// Cards he applied as entering that are not on the on-call board yet: Apply was cut short.
    var onCallUnfinished: [String] {
        let onBoard = Set(onCallQuest?.cards.map(\.id) ?? [])
        var ids: [String] = []
        for item in onCall.review?.items ?? [] where item.enters && item.applied != nil {
            guard let code = item.issue, !onCallOthers.contains(code) else { continue }
            let id = item.currentParent.flatMap { onCall.groups[$0] != nil ? $0 : nil } ?? code
            if !onBoard.contains(id) && !ids.contains(id) { ids.append(id) }
        }
        return ids
    }

    /// Start on an on-call card with no agent: its worktree under the shift's parent and the investigation agent.
    func startOnCallAgent(_ piece: Piece) async {
        guard !startingAgents.contains(piece.id) else { return }
        startingAgents.insert(piece.id)
        defer { startingAgents.remove(piece.id) }
        do {
            let parent = try await OnCall.parentWorktree(shift: OnCall.shiftRun(onCall.shiftDays))
            let path = try await OnCall.cardWorktree(piece.id, tag: piece.tag, parent: parent)
            try await Orca.startAgent(in: path, title: "\(piece.id) — \(piece.tag)",
                                      prompt: OnCall.kickoff(id: piece.id, title: piece.title, url: piece.url?.absoluteString ?? "", slack: nil))
            editOnCall { if !$0.launched.contains(piece.id) { $0.launched.append(piece.id) } }
        } catch {
            onCallNotice = "\(piece.id) could not be started: \(error.localizedDescription)"
        }
        await refresh()
    }
}
