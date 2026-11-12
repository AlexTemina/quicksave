import Foundation

/// What a decision on a Triage card writes in Linear, and what undoing it writes back.
/// Accepting is `Todo` with a due date (the agent executes it), rejecting is `Canceled`, already done is `Done`.
enum InboxWrites {
    static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date())
    }

    static func write(_ decision: InboxDecision, for item: TriageItem) async throws {
        switch decision {
        case .accept:
            try await Orca.linearWrite(["save-issue", item.id, "--state", "Todo", "--due-date", today()]) { await isIn(item.id, "Todo") }
        case .correct(let text):
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("quicksave-\(UUID().uuidString).md")
            try rewrittenDescription(item.rawDescription, willDo: text).write(to: file, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: file) }
            try await Orca.linearWrite(["save-issue", item.id, "--state", "Todo", "--due-date", today(), "--body-file", file.path])
        case .reject:
            try await Orca.linearWrite(["save-issue", item.id, "--state", "Canceled"]) { await isIn(item.id, "Canceled") }
        case .alreadyDone:
            try await Orca.linearWrite(["save-issue", item.id, "--state", "Done"]) { await isIn(item.id, "Done") }
        case .backlog:
            try await Orca.linearWrite(["save-issue", item.id, "--state", "Backlog"]) { await isIn(item.id, "Backlog") }
        case .instruct:
            break
        }
    }

    /// An expired issue: today keeps it with today's date, a correction is a new date (yyyy-MM-dd), backlog drops
    /// the date, reject cancels it and already done closes it.
    static func write(_ decision: InboxDecision, for item: ExpiredItem) async throws {
        let id = item.id
        switch decision {
        case .accept:
            try await Orca.linearWrite(["save-issue", id, "--due-date", today()])
        case .correct(let date):
            guard item.canPostpone else { throw QuicksaveError.message("\(id) was already postponed \(item.postpones) times.") }
            try await Orca.linearWrite(["save-issue", id, "--due-date", date])
        case .backlog:
            try await Orca.linearWrite(["save-issue", id, "--state", "Backlog", "--due-date", "null"]) { await isIn(id, "Backlog") }
        case .reject:
            try await Orca.linearWrite(["save-issue", id, "--state", "Canceled"]) { await isIn(id, "Canceled") }
        case .alreadyDone:
            try await Orca.linearWrite(["save-issue", id, "--state", "Done"]) { await isIn(id, "Done") }
        case .instruct:
            break // carried out by an agent, see Store.decide
        }
    }

    /// Puts an expired issue back as it was: its state and its old due date.
    static func undo(_ item: ExpiredItem) async throws {
        try await Orca.linearWrite(["save-issue", item.id, "--state", item.issue.state.name, "--due-date", item.issue.dueDate ?? "null"]) {
            await isIn(item.id, item.issue.state.name)
        }
    }

    /// Moves an item to a state by its name, e.g. "Done" or "Pending for inputs".
    static func setState(_ id: String, _ state: String) async throws {
        try await Orca.linearWrite(["save-issue", id, "--state", state]) { await isIn(id, state) }
    }

    /// Reads the state back, for a write Orca could not confirm.
    static func isIn(_ id: String, _ state: String) async -> Bool {
        guard let key = Database.shared.secret("linearApiKey") else { return false }
        return (try? await Linear.issueState(key: key, id: id)) == state
    }

    /// Back to Triage. An accepted item also loses the due date it was given; a corrected one keeps his edited text.
    static func undo(_ decision: InboxDecision, for item: TriageItem) async throws {
        var args = ["save-issue", item.id, "--state", "Triage"]
        if decision.needsAgent { args += ["--due-date", "null"] }
        try await Orca.linearWrite(args) { await isIn(item.id, "Triage") }
    }

    /// The same description with the lines under `## Will do` replaced by his, one bullet per line.
    static func rewrittenDescription(_ raw: String, willDo text: String) -> String {
        let bullets = text.components(separatedBy: "\n").compactMap { line -> String? in
            var t = line.trimmingCharacters(in: .whitespaces)
            for prefix in ["- ", "* "] where t.hasPrefix(prefix) { t = String(t.dropFirst(prefix.count)); break }
            return t.isEmpty ? nil : "* " + t
        }
        let lines = raw.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == "## will do" }) else {
            return (lines + ["", "## Will do", ""] + bullets).joined(separator: "\n")
        }
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("## ") } ?? lines.count
        var out = Array(lines[...start])
        out += [""] + bullets
        if end < lines.count { out += [""] + lines[end...] }
        return out.joined(separator: "\n")
    }
}
