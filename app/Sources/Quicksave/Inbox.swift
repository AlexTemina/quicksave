import Foundation

/// An item the auditor filed in Triage. Its description follows the auditor's own shape:
/// a `**Source:**` line, then `## Will do` and `## Why` bullets.
struct TriageItem: Identifiable, Hashable {
    let id: String
    let title: String
    let url: URL?
    let sourceLabel: String?
    let sourceURL: URL?
    /// The description as Linear holds it, needed to rewrite its "Will do" when he corrects a card.
    let rawDescription: String
    /// What happened, in the auditor's own words: the paragraph before "Will do".
    let intro: [String]
    let willDo: [String]
    let why: [String]
    let created: Date?

    init(_ issue: LinearIssue) {
        id = issue.identifier
        title = issue.title
        url = URL(string: issue.url)
        created = issue.createdAt.flatMap(QSDate.parse)
        rawDescription = issue.description ?? ""

        var source: (String, URL)?
        var sections: [String: [String]] = [:]
        var loose: [String] = []
        var current = ""
        let link = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(<?([^)>]+)>?\)"#)
        for raw in (issue.description ?? "").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") { current = line.dropFirst(3).lowercased().trimmingCharacters(in: .whitespaces); continue }
            guard !line.isEmpty else { continue }
            if current.isEmpty, line.lowercased().hasPrefix("**source:**") {
                let ns = line as NSString
                if let m = link.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                   let u = URL(string: ns.substring(with: m.range(at: 2))) {
                    source = (ns.substring(with: m.range(at: 1)), u)
                }
                continue
            }
            var text = line
            for prefix in ["* ", "- "] where text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)); break }
            text = MainQuest.clean(text)
            if current.isEmpty { loose.append(text) } else { sections[current, default: []].append(text) }
        }
        sourceLabel = source?.0
        sourceURL = source?.1
        // The text before "Will do" is what happened. An item without the auditor's headings
        // still shows what it says as its "Will do", never nothing.
        if let planned = sections["will do"] {
            intro = loose
            willDo = planned
        } else {
            intro = []
            willDo = loose.isEmpty ? [title] : loose
        }
        why = sections["why"] ?? []
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

    var id: String {
        switch self {
        case .triage(let t): return t.id
        case .pullRequest(let p): return p.id
        }
    }

    var created: Date? {
        switch self {
        case .triage(let t): return t.created
        case .pullRequest(let p): return p.created
        }
    }

    var label: String {
        switch self {
        case .triage(let t): return t.id
        case .pullRequest(let p): return "#\(p.number)"
        }
    }
}

/// What he decided about a card. Four decisions, as in `docs/inbox.md`.
enum InboxDecision: Hashable {
    case accept
    case correct(String)
    case reject
    case alreadyDone

    /// Accepting hands work to the agent; rejecting or already done does not.
    var needsAgent: Bool {
        switch self {
        case .accept, .correct: return true
        case .reject, .alreadyDone: return false
        }
    }

    var verb: String {
        switch self {
        case .accept: return "Accepted"
        case .correct: return "Accepted with a correction"
        case .reject: return "Rejected"
        case .alreadyDone: return "Marked done"
        }
    }

    /// How a decision about a pull request is remembered in the local database.
    var prRaw: String? {
        switch self {
        case .accept: return "accept"
        case .reject: return "reject"
        case .alreadyDone: return "done"
        case .correct: return nil
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
