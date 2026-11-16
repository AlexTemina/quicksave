import AppKit
import SwiftUI

/// The week's contract: the open TEMI issue with the label `Weekly Contract` (since 12-nov), shown at the top of
/// Today. Its description lists the objectives, one line each: `1. [P0] What is true on Tuesday: ES-1 (tag), ES-2 (tag)`.
struct WeeklyContract: Equatable {
    struct Issue: Equatable, Hashable { let id: String; let tag: String; let url: URL? }
    struct Objective: Equatable, Identifiable {
        let number: String
        let priority: String?
        let text: String
        let issues: [Issue]
        let serves: String?
        var id: String { number }
    }

    static let label = "Weekly Contract"

    let code: String
    let url: URL?
    let start: Date?
    let title: String
    let note: String?
    let objectives: [Objective]
    let carried: [String]

    var end: Date? { start.flatMap { Calendar.current.date(byAdding: .day, value: 6, to: $0) } }
    var allIssues: [String] { objectives.flatMap { $0.issues.map(\.id) } }

    /// "11 Nov → 17 Nov".
    var range: String {
        guard let start, let end else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "d MMM"
        return "\(f.string(from: start)) → \(f.string(from: end))"
    }

    /// Days left in the week, counting today: 1 on its last day, 0 once it is over.
    var daysLeft: Int {
        guard let end else { return 0 }
        let today = Calendar.current.startOfDay(for: Date())
        return max(0, (Calendar.current.dateComponents([.day], from: today, to: end).day ?? -1) + 1)
    }

    /// The open contract in Linear. Its due date is the Tuesday that closes the week, so the week starts six days before.
    static func current(key: String) async -> WeeklyContract? {
        guard let issue = try? await Linear.myOpenIssues(key: key, label: label).sorted(by: { ($0.dueDate ?? "") > ($1.dueDate ?? "") }).first,
              let text = try? await Linear.description(key: key, id: issue.identifier) else { return nil }
        let start = issue.dueDate.flatMap(QSDate.day).flatMap { Calendar.current.date(byAdding: .day, value: -6, to: $0) }
        return parse(text, code: issue.identifier, url: URL(string: issue.url), title: issue.title, start: start)
    }

    static func parse(_ text: String, code: String, url: URL?, title: String, start: Date?) -> WeeklyContract {
        var note: String?, objectives: [Objective] = [], carried: [String] = []
        var section = ""
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\[", with: "[").replacingOccurrences(of: "\\]", with: "]")
            if line.isEmpty { continue }
            if line.hasPrefix("#") { section = line.lowercased(); continue }
            if section.isEmpty { if note == nil { note = line }; continue }
            if section.contains("objective"), let r = line.range(of: #"^(\d+)\.\s+"#, options: .regularExpression) {
                objectives.append(objective(String(line[r.upperBound...]), number: line[r].filter(\.isNumber)))
            } else if section.contains("carried"), line.hasPrefix("- ") || line.hasPrefix("* ") {
                carried.append(String(line.dropFirst(2)))
            }
        }
        return WeeklyContract(code: code, url: url, start: start, title: title, note: note, objectives: objectives, carried: carried)
    }

    /// "[P0] What is true: ES-1 (tag), ES-2 (tag)". Linear may hand the codes back as plain text, markdown links or
    /// `<issue label="ES-1" href="…" />` mentions; all three are read.
    static func objective(_ item: String, number: String) -> Objective {
        var rest = item
        var priority: String?
        if let r = rest.range(of: #"^\[(P\d)\]\s*"#, options: .regularExpression) {
            priority = String(rest[r]).trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            rest = String(rest[r.upperBound...])
        }
        var urls: [String: URL] = [:]
        let mention = try! NSRegularExpression(pattern: #"<issue[^>]*label="([A-Z]+-\d+)"[^>]*href="([^"]+)"[^>]*/>"#)
        let link = try! NSRegularExpression(pattern: #"\[([A-Z]+-\d+)[^\]]*\]\(([^)]+)\)"#)
        for re in [mention, link] {
            let ns = rest as NSString
            for m in re.matches(in: rest, range: NSRange(location: 0, length: ns.length)) {
                urls[ns.substring(with: m.range(at: 1))] = URL(string: ns.substring(with: m.range(at: 2)))
            }
            rest = re.stringByReplacingMatches(in: rest, range: NSRange(location: 0, length: ns.length), withTemplate: "$1")
        }
        var what = rest, tail = ""
        if let r = rest.range(of: #":\s*(?=[A-Z]+-\d+)"#, options: .regularExpression) {
            what = String(rest[..<r.lowerBound]); tail = String(rest[r.upperBound...])
        }
        let code = try! NSRegularExpression(pattern: #"([A-Z]+-\d+)(?:\s*\(([^)]*)\))?"#)
        let ns = tail as NSString
        let issues = code.matches(in: tail, range: NSRange(location: 0, length: ns.length)).map { m -> Issue in
            let id = ns.substring(with: m.range(at: 1))
            let tag = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
            return Issue(id: id, tag: tag, url: urls[id] ?? URL(string: "https://linear.app/alan-eu/issue/\(id)"))
        }
        var serves: String?
        if let r = what.range(of: #"\.?\s*Serves [^.]*"#, options: .regularExpression) {
            serves = what[r].trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            what.removeSubrange(r)
        }
        return Objective(number: number, priority: priority, text: what.trimmingCharacters(in: .whitespaces), issues: issues, serves: serves)
    }
}

/// The contract at the top of Today: one tile per objective, its issues done over total as a bar.
struct WeekContractCard: View {
    let contract: WeeklyContract
    let issues: [String: Linear.QueueIssue]
    let color: (String) -> Color
    @State private var showCarried = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                QSLabel("This week", icon: "scroll", accent: true)
                Text(contract.range).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                let left = contract.daysLeft
                Text(left == 0 ? "Over: a new contract is due" : left == 1 ? "Last day" : "\(left) days left")
                    .font(Theme.Text.meta).foregroundStyle(left <= 1 ? Theme.Palette.warning : Theme.Palette.textTertiary)
                Spacer()
                let done = objectivesDone
                Text("\(done) of \(contract.objectives.count) objectives done").font(Theme.Text.number)
                    .foregroundStyle(done == contract.objectives.count && done > 0 ? .yellow : Theme.Palette.textSecondary)
                if let url = contract.url { QSIconButton(systemImage: "arrow.up.right.square", help: "Open \(contract.code) in Linear") { NSWorkspace.shared.open(url) } }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: Theme.Space.m, alignment: .top)], alignment: .leading, spacing: Theme.Space.m) {
                ForEach(contract.objectives) { tile($0) }
            }
            if !contract.carried.isEmpty {
                Button { withAnimation(Theme.Motion.hover) { showCarried.toggle() } } label: {
                    Label("Carried over (\(contract.carried.count))", systemImage: showCarried ? "chevron.down" : "chevron.right")
                        .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                }
                .buttonStyle(QSHoverStyle())
                if showCarried { QSBulletList(lines: contract.carried, secondary: true) }
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.xl).fill(Theme.Palette.raised)
            .shadow(color: Theme.Palette.shadow, radius: 6, y: 2))
    }

    private func isDone(_ id: String) -> Bool { ["completed", "canceled"].contains(issues[id]?.state.type ?? "") }

    private var objectivesDone: Int {
        contract.objectives.filter { o in !o.issues.isEmpty && o.issues.allSatisfy { isDone($0.id) } }.count
    }

    private func tile(_ o: WeeklyContract.Objective) -> some View {
        let done = o.issues.filter { isDone($0.id) }.count
        let complete = !o.issues.isEmpty && done == o.issues.count
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                if let p = o.priority { QSTag(text: p, icon: p == "P0" ? "flame.fill" : "flag.fill", color: priorityColor(p)) }
                Text(o.number).font(Theme.Text.code).foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                if complete { Image(systemName: Theme.Icon.questComplete).foregroundStyle(.yellow) }
            }
            MD(o.text).font(Theme.Text.body).fixedSize(horizontal: false, vertical: true)
            if !o.issues.isEmpty {
                HStack(spacing: Theme.Space.s) {
                    QSProgress(segments: o.issues.map { (priorityColor(o.priority ?? ""), isDone($0.id)) }, height: Theme.Size.miniBarHeight)
                    Text("\(done)/\(o.issues.count)").font(Theme.Text.micro).foregroundStyle(Theme.Palette.textTertiary)
                }
                QSFlow {
                    ForEach(o.issues, id: \.self) { issue in
                        QSLinkButton(url: issue.url, help: issue.id + (issues[issue.id].map { ": " + $0.state.name } ?? ""), padding: 0, backdrop: false) {
                            HStack(spacing: 4) {
                                QSDot(color: issues[issue.id].map { color($0.state.name) } ?? Theme.Palette.textTertiary, size: Theme.Size.smallDot)
                                Text(issue.id).font(Theme.Text.code)
                                Text(issue.tag).font(Theme.Text.micro).foregroundStyle(Theme.Palette.textSecondary)
                            }
                            .strikethrough(isDone(issue.id))
                            .padding(.horizontal, Theme.Space.s - 2).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.Palette.well))
                        }
                        .fixedSize()
                    }
                }
            }
            if let serves = o.serves {
                Text(serves).font(Theme.Text.micro).foregroundStyle(Theme.Palette.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.l).fill(complete ? Color.yellow.opacity(0.10) : Theme.Palette.well))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l).strokeBorder(complete ? Color.yellow.opacity(0.6) : .clear, lineWidth: 1))
    }

    private func priorityColor(_ p: String) -> Color {
        switch p {
        case "P0": return Theme.Palette.prFailing
        case "P1": return Theme.Palette.agentWaiting
        default: return Theme.Palette.agentIdle
        }
    }
}
