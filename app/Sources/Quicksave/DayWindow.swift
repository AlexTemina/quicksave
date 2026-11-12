import Foundation

/// What the morning must look at, decided by the app from Linear and handed to the plan, so nothing open is left out
/// in silence (10-nov: three overdue issues in progress were neither planned nor discarded). See docs/morning.md.
struct DayWindow {
    /// His issues the plan must place: due before the end of Alan's week or overdue, urgent or high, or in progress or
    /// in review. Each one ends up as a piece, a side quest, or left out with a reason.
    var mine: [Linear.WorkIssue] = []
    /// Medium, low or no-priority issues of his outside the window, untouched for longest first. One becomes a side
    /// quest every day, so the middle of the pile moves too.
    var slot: [Linear.WorkIssue] = []
    /// Issues of the projects he leads, not assigned to him, that fall in the same window.
    var projects: [(project: String, issues: [Linear.WorkIssue])] = []
    /// What could not be read, said plainly.
    var problems: [String] = []

    /// Alan's week ends on Wednesday: the coming one, today included.
    static func weekEnd(from day: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let weekday = cal.component(.weekday, from: day) // 1 Sunday … 4 Wednesday
        let ahead = (4 - weekday + 7) % 7
        let end = cal.date(byAdding: .day, value: ahead, to: day) ?? day
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.string(from: end)
    }

    /// Labels whose issues live elsewhere: the Main Quest itself, and the reading list.
    static func skipped(_ i: Linear.WorkIssue) -> Bool {
        i.labelNames.contains("Main Quest") || i.labelNames.contains("collectible")
    }

    static func inWindow(_ i: Linear.WorkIssue, end: String) -> Bool {
        if let due = i.dueDate, due <= end { return true }
        if [1, 2].contains(i.priority ?? 0) { return true }
        return ["In Progress", "In Review"].contains(i.state.name)
    }

    static func load(key: String) async -> DayWindow {
        var w = DayWindow()
        let end = weekEnd()
        do {
            let open = try await Linear.myWork(key: key).filter { !skipped($0) }
            w.mine = open.filter { inWindow($0, end: end) }.sorted(by: order)
            w.slot = Array(open.filter { i in
                !inWindow(i, end: end) && i.state.type == "unstarted" && i.state.name != "Pending for inputs"
                    && [0, 3, 4].contains(i.priority ?? 0)
            }.sorted { ($0.updatedAt ?? "") < ($1.updatedAt ?? "") }.prefix(3))
        } catch { w.problems.append("His issues: \(error.localizedDescription)") }
        do {
            w.projects = try await Linear.projectWork(key: key, until: end).map { p in
                (p.project, p.issues.filter { !skipped($0) && inWindow($0, end: end) }.sorted(by: order))
            }.filter { !$0.issues.isEmpty }
        } catch { w.problems.append("His projects: \(error.localizedDescription)") }
        return w
    }

    /// The 16-oct order: overdue and sooner first, any date before none, then priority.
    static func order(_ a: Linear.WorkIssue, _ b: Linear.WorkIssue) -> Bool {
        let da = a.dueDate ?? "9999", db = b.dueDate ?? "9999"
        if da != db { return da < db }
        let pa = a.priority == 0 || a.priority == nil ? 9 : a.priority!, pb = b.priority == 0 || b.priority == nil ? 9 : b.priority!
        return pa < pb
    }

    static func line(_ i: Linear.WorkIssue, withAssignee: Bool = false) -> String {
        var parts = ["\(i.identifier) \"\(i.title)\"", i.state.name, "due " + (i.dueDate ?? "none"), i.priorityName]
        if let p = i.project?.name { parts.append("project " + p) }
        if withAssignee { parts.append("assigned to " + (i.assignee?.name ?? "nobody")) }
        return "- " + parts.joined(separator: ", ") + " (" + i.url + ")"
    }

    /// The block the plan reads: what it must place, the medium slot, and the projects to watch.
    var prompt: String {
        let end = Self.weekEnd()
        var out = """
        What Quicksave read from Linear for you. Alan's week ends on \(end). Use these lists as they are; you may still read any issue for detail.

        1. The window: every open issue of his that is overdue or due by \(end), urgent or high, or in progress or in review. Every one of them must appear in your answer, by its code: as a piece, as a side quest, or in `discarded` with its reason. Overdue ones come first. None may be missing.
        \(mine.isEmpty ? "- (none)" : mine.map { Self.line($0) }.joined(separator: "\n"))

        2. The medium slot: one side quest a day comes from the middle of the pile, so it moves too. Pick the first of these unless it cannot be done today (then the next, and say why), and mark it with `slot: true`. Its why says how long it has waited.
        \(slot.isEmpty ? "- (none: leave the slot empty)" : slot.map { Self.line($0) }.joined(separator: "\n"))

        3. His projects: issues of projects he leads, not assigned to him, in the same window. He does not do them himself, but he must know what is moving. Put in `watch` the ones he should look at or act on today (blocked, overdue, waiting on him, risky for a date), one line each with why. Leave out the ones that are simply on track.
        """
        if projects.isEmpty { out += "\n- (none)" }
        for p in projects {
            out += "\n\(p.project):\n" + p.issues.map { Self.line($0, withAssignee: true) }.joined(separator: "\n")
        }
        if !problems.isEmpty { out += "\n\nCould not be read, so say so in failedSources: " + problems.joined(separator: "; ") }
        return out
    }

    /// Codes of the window the plan did not place anywhere.
    func missing(from plan: MorningPlan) -> [Linear.WorkIssue] {
        let text = ([plan.goal] + plan.pieces.compactMap(\.id) + (plan.sideQuests ?? []).map(\.id)
                    + plan.discarded.map { $0.what + " " + $0.why } + [plan.existing ?? ""]).joined(separator: " ")
        return mine.filter { !text.contains($0.identifier) }
    }
}

/// An overdue issue of his, as a card of the inbox: do it today, give it a new date, send it to the backlog, cancel it
/// or mark it done. After three postpones it can no longer be pushed: it is done today, or consciously dropped.
struct ExpiredItem: Identifiable, Hashable {
    static let maxPostpones = 3

    let issue: Linear.WorkIssue
    let description: String
    let postpones: Int
    var id: String { issue.identifier }
    var canPostpone: Bool { postpones < Self.maxPostpones }

    var daysLate: Int {
        guard let due = issue.dueDate, let d = QSDate.day(due) else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: d, to: Calendar.current.startOfDay(for: Date())).day ?? 0)
    }

    static func load(key: String) async throws -> [ExpiredItem] {
        let today = InboxWrites.today()
        let late = try await Linear.myWork(key: key).filter { i in
            !DayWindow.skipped(i) && (i.dueDate.map { $0 < today } ?? false)
        }
        let histories = try await Linear.histories(key: key, ids: late.map(\.identifier))
        return late.map { i in
            ExpiredItem(issue: i, description: histories[i.identifier]?.description ?? "", postpones: histories[i.identifier]?.postpones ?? 0)
        }.sorted { ($0.issue.dueDate ?? "") < ($1.issue.dueDate ?? "") }
    }
}
