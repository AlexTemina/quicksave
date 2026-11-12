import Foundation

/// An item the auditor filed in Triage. Its description follows the auditor's own shape: what happened, a
/// `**Source:**` line, then `## Will do` and `## Why` bullets, and sometimes more sections. Nothing of it is dropped:
/// what is not "Will do" or "Why" is kept as a section of its own.
struct TriageItem: Identifiable, Hashable {
    struct Section: Hashable { let title: String; let body: String }

    let id: String
    let title: String
    let url: URL?
    /// Where it came from, as written: plain text, a link, or both.
    let source: String?
    /// The description as Linear holds it, needed to rewrite its "Will do" when he corrects a card.
    let rawDescription: String
    /// What happened, in the auditor's own words: every line before the first heading, other than the source.
    let intro: [String]
    let willDo: [String]
    let why: [String]
    /// Any other section (QA, Context, Draft…), in order, as Markdown.
    let others: [Section]
    let created: Date?

    init(_ issue: LinearIssue) {
        id = issue.identifier
        title = issue.title
        url = URL(string: issue.url)
        created = issue.createdAt.flatMap(QSDate.parse)
        rawDescription = issue.description ?? ""

        var source: String?
        var loose: [String] = []
        var order: [String] = []
        var raw: [String: [String]] = [:]
        var current = ""
        for line in rawDescription.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                current = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if raw[current] == nil { order.append(current); raw[current] = [] }
                continue
            }
            if current.isEmpty {
                guard !trimmed.isEmpty else { continue }
                if trimmed.lowercased().hasPrefix("**source:**") {
                    source = MainQuest.clean(String(trimmed.dropFirst("**source:**".count)).trimmingCharacters(in: .whitespaces))
                } else {
                    loose.append(MainQuest.clean(trimmed))
                }
            } else {
                raw[current, default: []].append(line)
            }
        }
        self.source = source
        func bullets(_ lines: [String]) -> [String] {
            lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { line in
                var text = line
                for prefix in ["* ", "- "] where text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)); break }
                return MainQuest.clean(text)
            }
        }
        let willKey = order.first { $0.lowercased() == "will do" }
        let whyKey = order.first { $0.lowercased() == "why" }
        // An item without the auditor's headings still shows what it says as its "Will do", never nothing.
        if let willKey {
            intro = loose
            willDo = bullets(raw[willKey] ?? [])
        } else {
            intro = []
            willDo = loose.isEmpty ? [title] : loose
        }
        why = whyKey.map { bullets(raw[$0] ?? []) } ?? []
        others = order.filter { $0 != willKey && $0 != whyKey }.compactMap { key in
            let body = (raw[key] ?? []).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : Section(title: key, body: MainQuest.clean(body))
        }
    }
}

/// A pull request the auditor opened on the vault.
struct VaultPullRequest: Identifiable, Hashable {
    let number: Int
    let title: String
    let url: URL
    let body: String
    let additions: Int
    let deletions: Int
    let files: [String]
    let created: Date?
    let author: String

    var id: String { "PR-\(number)" }

    /// What the description says changes: its bullets, without the generator's signature line.
    var changes: [String] {
        body.components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
            return MainQuest.clean(String(line.dropFirst(2)))
        }
    }

    /// The first plain sentence of the description, for a pull request with no bullets.
    var summary: String {
        body.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasPrefix("*") && !$0.hasPrefix("🤖") && !$0.hasPrefix("#") } ?? ""
    }
}

/// One card of the deck: whatever is waiting for Alejandro's decision.
enum InboxCard: Identifiable, Hashable {
    case triage(TriageItem)
    case pullRequest(VaultPullRequest)
    /// One of his issues whose due date has passed.
    case expired(ExpiredItem)

    var id: String {
        switch self {
        case .triage(let t): return t.id
        case .pullRequest(let p): return p.id
        case .expired(let e): return e.id
        }
    }

    var created: Date? {
        switch self {
        case .triage(let t): return t.created
        case .pullRequest(let p): return p.created
        case .expired: return nil
        }
    }

    var label: String {
        switch self {
        case .triage(let t): return t.id
        case .pullRequest(let p): return "#\(p.number)"
        case .expired(let e): return e.id
        }
    }
}

/// What he decided about a card. Four decisions, as in `docs/inbox.md`.
enum InboxDecision: Hashable {
    case accept
    case correct(String)
    case reject
    case alreadyDone
    /// An expired issue sent to the backlog, without a date.
    case backlog
    /// What to do with an expired issue, in his words; an agent carries it out.
    case instruct(String)

    /// Accepting hands work to the agent; rejecting or already done does not.
    var needsAgent: Bool {
        switch self {
        case .accept, .correct, .instruct: return true
        case .reject, .alreadyDone, .backlog: return false
        }
    }

    var verb: String {
        switch self {
        case .accept: return "Accepted"
        case .correct: return "Accepted with a correction"
        case .reject: return "Rejected"
        case .alreadyDone: return "Marked done"
        case .backlog: return "Sent to the backlog"
        case .instruct: return "Handed to an agent"
        }
    }

    /// How a decision about a pull request is remembered in the local database.
    var prRaw: String? {
        switch self {
        case .accept: return "accept"
        case .reject: return "reject"
        case .alreadyDone: return "done"
        case .correct, .backlog, .instruct: return nil
        }
    }

    init?(prRaw: String) {
        switch prRaw {
        case "accept": self = .accept
        case "reject": self = .reject
        case "done": self = .alreadyDone
        default: return nil
        }
    }
}

/// What the agent hands back after applying, plus what the app itself did with pull requests.
struct ApplyReport: Identifiable {
    enum Outcome { case done, needsYou, failed, skipped }
    struct Row: Identifiable {
        let id = UUID()
        let ref: String
        let outcome: Outcome
        let summary: String
        let links: [URL]
        /// The worktree an agent worked in, so the row can jump to it.
        var worktree: Orca.Match?
    }
    struct Draft: Identifiable {
        let id = UUID()
        let place: String
        let note: String
        let link: URL?
        let text: String
    }
    let id = UUID()
    var rows: [Row] = []
    var drafts: [Draft] = []
    var notes: String = ""
    var denials: [String] = []
    var cost: Double?
    var seconds: Double?
}
