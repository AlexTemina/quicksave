import Foundation

enum Column: String, CaseIterable, Identifiable {
    case todo = "Todo", inProgress = "In Progress", inReview = "In Review", pending = "Pending for inputs", done = "Done"
    var id: String { rawValue }

    /// Linear's default colors, used until the workspace's own arrive.
    var fallbackHex: String {
        switch self {
        case .todo: return "#e2e2e2"
        case .inProgress: return "#f2c94c"
        case .inReview: return "#0f783c"
        case .pending: return "#eb5757"
        case .done: return "#5e6ad2"
        }
    }

    static func of(_ state: LinearIssue.State) -> Column {
        if let exact = Column(rawValue: state.name) { return exact }
        switch state.type {
        case "completed", "canceled": return .done
        case "started": return .inProgress
        default: return .todo
        }
    }
}

struct Piece: Identifiable {
    let id: String
    let title: String
    let stateName: String
    let description: String
    let tag: String
    let step: String
    let qa: [String]
    let url: URL?
    let column: Column
    let order: Int
}

struct MainQuest {
    let identifier: String
    let title: String
    let stateName: String
    let column: Column
    let done: String
    let dueDate: String?
    let url: URL?
    let pieces: [Piece]

    var doneCount: Int { pieces.filter { $0.column == .done }.count }
    var next: Piece? { pieces.sorted { $0.order < $1.order }.first { $0.column != .done } }

    /// The Main Quest's description is the plan: first line is what "done" means, then numbered pieces
    /// `1. [ES-123 (tag)](url): step.` in order. Everything else (state, QA) comes from the pieces themselves.
    init(_ issue: LinearIssue) {
        identifier = issue.identifier
        stateName = issue.state.name
        column = Column.of(issue.state)
        title = issue.title.replacingOccurrences(of: "Main Quest: ", with: "")
        dueDate = issue.dueDate
        url = URL(string: issue.url)
        let lines = (issue.description ?? "").components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        done = lines.first { !$0.isEmpty } ?? ""

        var planned: [String: (order: Int, tag: String, step: String)] = [:]
        let pattern = try! NSRegularExpression(pattern: #"^(\d+)\.\s*\[([A-Z]+-\d+)\s*(?:\(([^)]*)\))?\]\([^)]*\)\s*:?\s*(.*)$"#)
        for line in lines {
            let ns = line as NSString
            guard let m = pattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            func g(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
            planned[g(2)] = (Int(g(1)) ?? 99, g(3), Self.clean(g(4)))
        }

        var related: [LinearIssue] = []
        for r in issue.relations?.nodes ?? [] where r.type == "related" { if let i = r.relatedIssue { related.append(i) } }
        for r in issue.inverseRelations?.nodes ?? [] where r.type == "related" { if let i = r.issue { related.append(i) } }
        var seen = Set<String>()
        pieces = related.filter { seen.insert($0.identifier).inserted }.map { p in
            let plan = planned[p.identifier]
            return Piece(id: p.identifier, title: p.title, stateName: p.state.name,
                         description: Self.clean(p.description ?? ""), tag: plan?.tag.isEmpty == false ? plan!.tag : p.title,
                         step: plan?.step ?? "", qa: Self.qa(p.description), url: URL(string: p.url),
                         column: Column.of(p.state), order: plan?.order ?? 99)
        }.sorted { $0.order < $1.order }
    }

    /// Linear renders PR mentions as `<pull-request ... label="org/repo#123" ... />`; show them as `#123`.
    static func clean(_ text: String) -> String {
        let re = try! NSRegularExpression(pattern: ##"<pull-request[^>]*label="[^"#]*#(\d+)"[^>]*/>"##)
        let ns = text as NSString
        let tagged = re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "#$1")
        let long = try! NSRegularExpression(pattern: #"\[[\w.-]+/[\w.-]+#(\d+)\]"#)
        let t = tagged as NSString
        return long.stringByReplacingMatches(in: tagged, range: NSRange(location: 0, length: t.length), withTemplate: "[#$1]")
            .replacingOccurrences(of: "](<", with: "](").replacingOccurrences(of: ">)", with: ")")
    }

    static func qa(_ description: String?) -> [String] {
        var inQA = false, out: [String] = []
        for raw in (description ?? "").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { inQA = line.lowercased().hasPrefix("## qa"); continue }
            if inQA, line.hasPrefix("- ") || line.hasPrefix("* ") {
                out.append(clean(String(line.dropFirst(2)).replacingOccurrences(of: "[ ] ", with: "").replacingOccurrences(of: "[x] ", with: "✓ ")))
            }
        }
        return out
    }
}
