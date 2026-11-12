import AppKit
import SwiftUI

/// The week's contract, read from the newest `~/vault/Journal/*Weekly Contract.md` (read only), shown at the top of
/// Today: the week's objectives with their priority, the issues each one stands on and how many are done.
/// Where the contract lives is still to decide (10-nov); until then the vault's file is the source.
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

    let file: URL
    let start: Date?
    let title: String
    let note: String?
    let objectives: [Objective]
    let carried: [String]

    var end: Date? { start.flatMap { Calendar.current.date(byAdding: .day, value: 6, to: $0) } }
    var allIssues: [String] { objectives.flatMap { $0.issues.map(\.id) } }

    /// "4-nov → 10-nov".
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

    static func newest() -> WeeklyContract? {
        let dir = URL(fileURLWithPath: NSHomeDirectory() + "/vault/Journal")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
        guard let name = names.filter({ $0.hasSuffix("Weekly Contract.md") }).sorted().last else { return nil }
        let url = dir.appendingPathComponent(name)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text, file: url, date: String(name.prefix(10)))
    }

    static func parse(_ text: String, file: URL, date: String) -> WeeklyContract {
        var title = "", note: String?, objectives: [Objective] = [], carried: [String] = []
        var section = ""
        var inFront = false
        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "---" && (i == 0 || inFront) { inFront.toggle(); continue }
            if inFront { continue }
            if line.hasPrefix("# ") { title = String(line.dropFirst(2)); continue }
            if line.hasPrefix("## ") { section = line.lowercased(); continue }
            if line.hasPrefix(">"), note == nil { note = line.drop { $0 == ">" }.trimmingCharacters(in: .whitespaces); continue }
            guard line.hasPrefix("- ") else { continue }
            let item = String(line.dropFirst(2))
            if section.contains("objetivo") || section.contains("objective") { objectives.append(objective(item, index: objectives.count + 1)) }
            else if section.contains("arrastro") || section.contains("carry") { carried.append(item) }
        }
        return WeeklyContract(file: file, start: QSDate.day(date), title: title, note: note, objectives: objectives, carried: carried)
    }

    /// "**1.** [P0] What → [ES-1 — tag](url), [ES-2 — tag](url). Sirve a Mo M1 (4-nov)."
    static func objective(_ item: String, index: Int) -> Objective {
        var rest = item
        var number = "\(index)"
        if let r = rest.range(of: #"^\*\*(\d+)\.\*\*\s*"#, options: .regularExpression) {
            number = rest[r].filter(\.isNumber)
            rest = String(rest[r.upperBound...])
        }
        var priority: String?
        if let r = rest.range(of: #"^\[(P\d)\]\s*"#, options: .regularExpression) {
            priority = String(rest[r]).trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            rest = String(rest[r.upperBound...])
        }
        let parts = rest.components(separatedBy: "→")
        let what = parts[0].trimmingCharacters(in: .whitespaces)
        let tail = parts.count > 1 ? parts.dropFirst().joined(separator: "→") : rest
        let re = try! NSRegularExpression(pattern: #"\[([A-Z]+-\d+)\s*[—-]\s*([^\]]+)\]\(([^)]+)\)"#)
        let ns = tail as NSString
        let issues = re.matches(in: tail, range: NSRange(location: 0, length: ns.length)).map {
            Issue(id: ns.substring(with: $0.range(at: 1)), tag: ns.substring(with: $0.range(at: 2)), url: URL(string: ns.substring(with: $0.range(at: 3))))
        }
        var serves: String?
        if let r = tail.range(of: #"(Sirve a|Serves)[^.]*"#, options: .regularExpression) { serves = String(tail[r]) }
        return Objective(number: number, priority: priority, text: parts.count > 1 ? what : re.stringByReplacingMatches(in: what, range: NSRange(location: 0, length: (what as NSString).length), withTemplate: "$1"),
                         issues: issues, serves: serves)
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
                QSIconButton(systemImage: "doc.text", help: "Open the contract in the vault") { NSWorkspace.shared.open(contract.file) }
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
