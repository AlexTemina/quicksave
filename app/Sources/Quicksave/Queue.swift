import AppKit
import SwiftUI

/// The day beyond the Main Quest: the side quests that fit today, and the collectibles. Side quests are the plan,
/// so they live in Linear, in the Main Quest's description under `## Side quests`; the app keeps no list of its own.
/// Collectibles are his open issues with the `collectible` label. See docs/board.md.

enum SideQuestPlan {
    struct Line: Hashable { let id: String; var tag: String = ""; let note: String }

    static let heading = "## Side quests"

    private static func isHeading(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix(heading.lowercased())
    }

    /// The section's lines: where it starts and where it ends (exclusive), if it exists.
    private static func section(_ lines: [String]) -> Range<Int>? {
        guard let start = lines.firstIndex(where: isHeading) else { return nil }
        let end = lines[(start + 1)...].firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("## ") } ?? lines.count
        return start..<end
    }

    /// The side quests written in a Main Quest's description, in order.
    static func parse(_ description: String) -> [Line] {
        let lines = description.components(separatedBy: "\n")
        guard let range = section(lines) else { return [] }
        let code = try! NSRegularExpression(pattern: #"[A-Z]+-\d+"#)
        var out: [Line] = []
        for line in lines[range].dropFirst() {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("- ") || t.hasPrefix("* ") else { continue }
            let ns = t as NSString
            guard let m = code.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { continue }
            let id = ns.substring(with: m.range)
            guard !out.contains(where: { $0.id == id }) else { continue }
            // What follows the link, after its colon, is the note: why it is in today.
            var note = ""
            if let link = t.range(of: "]("), let close = t[link.upperBound...].firstIndex(of: ")"),
               let colon = t[t.index(after: close)...].firstIndex(of: ":") {
                note = MainQuest.clean(String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
            }
            // The tag is what sits in the brackets after the code: "[ES-123 (tag)](url)".
            var tag = ""
            if let start = t.range(of: id + " ("), let end = t.range(of: ")](", range: start.upperBound..<t.endIndex) {
                tag = MainQuest.clean(String(t[start.upperBound..<end.lowerBound]))
            }
            out.append(Line(id: id, tag: tag, note: note))
        }
        return out
    }

    static func line(_ issue: Linear.QueueIssue) -> String {
        "- [\(issue.identifier) (\(issue.title))](\(issue.url))"
    }

    /// A side quest the morning plan proposed, with why it is in today.
    static func line(_ side: MorningPlan.Side) -> String {
        let url = side.url.flatMap { $0.isEmpty ? nil : $0 } ?? "https://linear.app/alan-eu/issue/\(side.id)"
        return "- [\(side.id) (\(tag(side.title, id: side.id)))](\(url)): \(side.why)"
    }

    /// The tag without the code an agent sometimes puts in it: "TEMI-554 (Alfredo's MBR update)" is "Alfredo's MBR update".
    static func tag(_ title: String, id: String) -> String {
        var t = title.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix(id) else { return t }
        t = String(t.dropFirst(id.count)).trimmingCharacters(in: CharacterSet(charactersIn: " :-"))
        if t.hasPrefix("("), t.hasSuffix(")") { t = String(t.dropFirst().dropLast()) }
        return t.isEmpty ? title : t
    }

    /// The description with its side quests section replaced by these lines, created before `## QA` if missing.
    static func replacing(_ newLines: [String], in description: String) -> String {
        var lines = description.components(separatedBy: "\n")
        if let range = section(lines) {
            lines.replaceSubrange(range, with: [heading, ""] + newLines + [""])
        } else if let qa = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("## qa") }) {
            lines.insert(contentsOf: [heading, ""] + newLines + [""], at: qa)
        } else {
            lines += ["", heading, ""] + newLines
        }
        return lines.joined(separator: "\n")
    }

    /// The description with one more side quest at the end of the section. The section is created before
    /// `## QA` when there is none yet.
    static func adding(_ issue: Linear.QueueIssue, to description: String) -> String {
        var lines = description.components(separatedBy: "\n")
        if parse(description).contains(where: { $0.id == issue.identifier }) { return description }
        if let range = section(lines) {
            var at = range.upperBound
            while at > range.lowerBound + 1, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
            lines.insert(line(issue), at: at)
        } else if let qa = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("## qa") }) {
            lines.insert(contentsOf: [heading, "", line(issue), ""], at: qa)
        } else {
            lines += ["", heading, "", line(issue)]
        }
        return lines.joined(separator: "\n")
    }

    static func removing(_ id: String, from description: String) -> String {
        var lines = description.components(separatedBy: "\n")
        guard let range = section(lines) else { return description }
        let drop = range.dropFirst().filter { i in
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            return (t.hasPrefix("- ") || t.hasPrefix("* ")) && t.contains(id)
        }
        for i in drop.reversed() { lines.remove(at: i) }
        return lines.joined(separator: "\n")
    }
}

/// The order of the 16-oct rule: due today or overdue, then any date before no date and sooner first,
/// then Linear priority, then size, small first.
enum QueueOrder {
    static func sorted(_ issues: [Linear.QueueIssue]) -> [Linear.QueueIssue] {
        let today = Morning.today
        func key(_ i: Linear.QueueIssue) -> (Int, String, Int, Double) {
            let bucket = i.dueDate.map { $0 <= today ? 0 : 1 } ?? 2
            let priority = (i.priority ?? 0) == 0 ? 5 : i.priority!
            return (bucket, i.dueDate ?? "9999", priority, i.estimate ?? 99)
        }
        return issues.sorted { key($0) < key($1) }
    }
}

/// Writes to the plan: today's side quests. The description is read fresh from Linear just before, so nothing written
/// there in the meantime is lost. Every side quest is also linked to the Main Quest as related, so Linear shows it
/// next to it; one taken out of the list loses that link.
enum PlanWrites {
    static func change(mainQuest: String, _ edit: (String) -> String) async throws {
        guard let key = Database.shared.secret("linearApiKey") else { throw QuicksaveError.message("No Linear API key in Settings.") }
        let before = try await Linear.description(key: key, id: mainQuest)
        let after = edit(before)
        guard after != before else { return }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("quicksave-\(UUID().uuidString).md")
        try after.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let wanted = SideQuestPlan.parse(after).map(\.id)
        try await Orca.linearWrite(["save-issue", mainQuest, "--body-file", file.path]) {
            // Linear rewrites Markdown a little (bullets, links), so the read-back compares the side quests, not the text.
            guard let now = try? await Linear.description(key: key, id: mainQuest) else { return false }
            return SideQuestPlan.parse(now).map(\.id) == wanted
        }

        let old = Set(SideQuestPlan.parse(before).map(\.id)), new = Set(SideQuestPlan.parse(after).map(\.id))
        for id in new.subtracting(old) {
            // An existing link answers with an error, which is fine: the link is there.
            try? await Orca.linearWrite(["relation", "add", mainQuest, "--related", id, "--type", "related"])
        }
        for id in old.subtracting(new) {
            try? await Orca.linearWrite(["relation", "remove", mainQuest, "--related", id, "--type", "related"])
        }
    }
}

// MARK: Board sections

struct SideQuestsSection: View {
    @ObservedObject var store: Store
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                QSLabel("Side Quests", icon: Theme.Icon.sideQuests)
                if !store.sideQuests.isEmpty {
                    QSProgress(segments: store.sideQuests.map { (Theme.Palette.questSide, $0.column == .done) })
                        .frame(maxWidth: 220)
                    Text("\(store.sideQuests.filter { $0.column == .done }.count) of \(store.sideQuests.count) done")
                        .font(Theme.Text.number).foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                if store.quest != nil {
                    Button { picking = true } label: { Label("Add to today", systemImage: "plus") }
                        .buttonStyle(QSHoverStyle()).font(Theme.Text.meta)
                        .popover(isPresented: $picking, arrowEdge: .bottom) { AddToTodayPicker(store: store) { picking = false } }
                }
            }
            if let notice = store.planNotice { QSNote(text: notice, icon: "exclamationmark.triangle", warning: true) }
            if store.quest == nil {
                QSPlaceholder(text: "Side quests come with the day's plan.")
            } else if store.sideQuests.isEmpty {
                QSPlaceholder(text: "Nothing else today. Add one if something fits.")
            } else {
                StateBoard(store: store, items: store.sideQuests, column: \.column) { piece in
                    PieceCard(piece: piece, store: store) { Task { await store.removeFromToday(piece.id) } }
                }
            }
        }
    }
}

struct CollectiblesSection: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                QSLabel("Collectibles", icon: Theme.Icon.collectibles)
                if !store.collectibles.isEmpty {
                    Text("\(store.collectibles.count)").font(Theme.Text.label).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            if store.collectibles.isEmpty {
                QSPlaceholder(text: "Issues with the collectible label show up here.")
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ForEach(store.collectibles) { issue in
                        QSLinkButton(url: URL(string: issue.url), padding: Theme.Space.xs) {
                            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                                Image(systemName: issue.title.hasPrefix("Watch") ? "play.rectangle" : "book")
                                    .foregroundStyle(Theme.Palette.textTertiary)
                                Text(Self.shortTitle(issue.title)).font(Theme.Text.body).lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: Theme.Space.s)
                                if let due = issue.dueDate { QSDue(ymd: due, done: false) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .padding(Theme.Space.s)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.l).fill(Theme.Palette.well))
            }
        }
    }

    /// "Read: Eng Gazette" reads as "Eng Gazette": the icon already says read or watch.
    static func shortTitle(_ title: String) -> String {
        for prefix in ["Read: ", "Watch: "] where title.hasPrefix(prefix) { return String(title.dropFirst(prefix.count)) }
        return title
    }
}

/// A due date as a small chip: red once it has passed.
struct QSDue: View {
    let ymd: String
    let done: Bool
    var body: some View {
        let late = !done && ymd < Morning.today
        Label(QSDate.friendly(ymd), systemImage: Theme.Icon.due)
            .font(Theme.Text.micro)
            .foregroundStyle(late ? Theme.Palette.prFailing : Theme.Palette.textTertiary)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Picks one of his open issues to add to today's side quests, in queue order.
struct AddToTodayPicker: View {
    @ObservedObject var store: Store
    let close: () -> Void
    @State private var search = ""
    @State private var issues: [Linear.QueueIssue] = []
    @State private var loading = true

    private var shown: [Linear.QueueIssue] {
        let q = search.lowercased()
        return q.isEmpty ? issues : issues.filter { $0.title.lowercased().contains(q) || $0.identifier.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Add to today").font(Theme.Text.cardTitle)
            TextField("Search your open issues", text: $search)
                .textFieldStyle(.plain)
                .padding(Theme.Space.s)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.well))
            if loading {
                HStack(spacing: Theme.Space.s) { ProgressView().controlSize(.small); Text("Loading…").font(Theme.Text.meta) }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(shown) { issue in
                            Button {
                                close()
                                Task { await store.addToToday(issue) }
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                                    Text(issue.identifier).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                                        .frame(width: 78, alignment: .leading)
                                    Text(issue.title).font(Theme.Text.body).lineLimit(1)
                                    Spacer(minLength: Theme.Space.s)
                                    if let due = issue.dueDate { QSDue(ymd: due, done: false) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(QSHoverStyle())
                        }
                        if shown.isEmpty { Text("Nothing matches.").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary) }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: Theme.Size.pickerWidth)
        .task {
            issues = await store.issuesToAdd()
            loading = false
        }
    }
}
