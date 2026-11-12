import SwiftUI

/// Inline Markdown from Linear (bold, italic, `code`, links), rendered as a SwiftUI Text. Falls back to plain text.
struct MD: View {
    let source: String
    init(_ source: String) { self.source = source }
    @State private var hovering = false
    @State private var hoveredLink: HoveredLink?
    @State private var rects = LinkRects()
    @Environment(\.linkPreviewsEnabled) private var previewsEnabled

    var body: some View {
        let hasLinks = source.contains("](")
        let attributed = Self.attributed(source, emphasizeLinks: hasLinks && hovering)
        if hasLinks && previewsEnabled && Self.hasPreviewableLink(attributed) {
            // Links Quicksave can read get a hover card: the renderer notes where each one is drawn.
            Self.text(attributed)
                .textRenderer(LinkTrackingRenderer(box: rects))
                .tint(Theme.Palette.link)
                .lineSpacing(Theme.Leading.body)
                .fixedSize(horizontal: false, vertical: true)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hovering = true
                        let hit = rects.rects.first { $0.1.insetBy(dx: -1, dy: -2).contains(point) }
                        let next = hit.map { HoveredLink(target: $0.0, rect: $0.1) }
                        if next?.target != hoveredLink?.target { hoveredLink = next }
                    case .ended:
                        hovering = false
                        hoveredLink = nil
                    }
                }
                .animation(Theme.Motion.hover, value: hovering)
                .modifier(LinkPreviewHost(hovered: hoveredLink))
        } else {
            Text(attributed)
                .tint(Theme.Palette.link)
                .lineSpacing(Theme.Leading.body)
                .fixedSize(horizontal: false, vertical: true)
                .onHover { hovering = $0 }
                .animation(Theme.Motion.hover, value: hovering)
        }
    }

    static func hasPreviewableLink(_ text: AttributedString) -> Bool {
        text.runs.contains { $0.link.flatMap(LinkTarget.init) != nil }
    }

    /// The same text, built run by run so the links Quicksave can read carry a mark the renderer finds.
    static func text(_ attributed: AttributedString) -> Text {
        var out = Text("")
        for run in attributed.runs {
            let piece = Text(AttributedString(attributed[run.range]))
            if let target = run.link.flatMap(LinkTarget.init) {
                out = out + piece.customAttribute(LinkAttribute(target: target))
            } else {
                out = out + piece
            }
        }
        return out
    }

    /// Links are blue; while the pointer is over the text they underline and brighten, so they read as clickable.
    static func attributed(_ s: String, emphasizeLinks: Bool = false) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var text = (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
        for run in text.runs where run.link != nil {
            text[run.range].foregroundColor = emphasizeLinks ? Theme.Palette.linkHover : Theme.Palette.link
            if emphasizeLinks { text[run.range].underlineStyle = .single }
        }
        for run in text.runs where run.inlinePresentationIntent?.contains(.code) == true {
            text[run.range].font = .system(.callout, design: .monospaced)
            text[run.range].backgroundColor = Color.secondary.opacity(0.15)
        }
        return text
    }
}

/// Minimal block Markdown for issue descriptions: headings, bullets, checkboxes, numbered lists, code fences.
/// Linear's collapsible `+++ Title` sections are shown folded to their title.
struct MarkdownBlock: View {
    let source: String
    init(_ source: String) { self.source = source }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            ForEach(Array(Self.blocks(source).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let t): MD(t).font(.headline).padding(.top, 6)
                case .bullet(let mark, let t, let indent):
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(mark).foregroundStyle(.secondary)
                        MD(t)
                    }.padding(.leading, CGFloat(indent) * 14)
                case .code(let t):
                    Text(t).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                case .folded(let t): Label(t, systemImage: "chevron.right").font(.caption).foregroundStyle(.secondary)
                case .paragraph(let t): MD(t)
                case .table(let header, let rows): MarkdownTable(header: header, rows: rows)
                case .quote(let t):
                    MD(t).foregroundStyle(.secondary).padding(.leading, Theme.Space.m)
                        .overlay(alignment: .leading) { Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 3) }
                case .rule: Divider()
                }
            }
        }
        .textSelection(.enabled)
    }

    enum Block { case heading(String), bullet(String, String, Int), code(String), folded(String), paragraph(String), table([String], [[String]]), quote(String), rule }

    static func blocks(_ s: String) -> [Block] {
        var out: [Block] = [], code: [String]? = nil, folded = false, table: [[String]] = []
        func cells(_ line: String) -> [String] {
            var l = Substring(line)
            if l.hasPrefix("|") { l = l.dropFirst() }
            if l.hasSuffix("|") { l = l.dropLast() }
            return l.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        func flushTable() {
            guard !table.isEmpty else { return }
            out.append(.table(table[0], Array(table.dropFirst())))
            table = []
        }
        for raw in s.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // A table: consecutive lines starting with "|"; the "|---|---|" line under the header is dropped.
            if code == nil, !folded, line.hasPrefix("|") {
                if line.range(of: #"^\|?[\s:|-]+\|?$"#, options: .regularExpression) == nil { table.append(cells(line)) }
                continue
            }
            flushTable()
            if line.hasPrefix("```") {
                if let c = code { out.append(.code(c.joined(separator: "\n"))); code = nil } else { code = [] }
                continue
            }
            if code != nil { code!.append(raw); continue }
            if line.hasPrefix("+++") {
                let title = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                if folded { folded = false } else { folded = true; out.append(.folded(title.isEmpty ? "More" : title)) }
                continue
            }
            if folded || line.isEmpty { continue }
            let indent = (raw.prefix { $0 == " " }.count) / 2
            if line.range(of: #"^(-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil { out.append(.rule); continue }
            if line.hasPrefix(">") { out.append(.quote(line.drop { $0 == ">" }.trimmingCharacters(in: .whitespaces))); continue }
            if line.hasPrefix("#") { out.append(.heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))); continue }
            if let (prefix, mark) = [("- [ ] ", "☐"), ("* [ ] ", "☐"), ("- [x] ", "☑"), ("* [x] ", "☑"), ("- ", "•"), ("* ", "•")]
                .first(where: { line.hasPrefix($0.0) }) {
                out.append(.bullet(mark, String(line.dropFirst(prefix.count)), indent)); continue
            }
            if let r = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                out.append(.bullet(String(line[r]).trimmingCharacters(in: .whitespaces), String(line[r.upperBound...]), indent)); continue
            }
            out.append(.paragraph(line))
        }
        flushTable()
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        return out
    }
}

/// A Markdown table: a bold header, a hairline under it and between rows, columns sized to their content.
struct MarkdownTable: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        let width = max(header.count, rows.map(\.count).max() ?? 0)
        Grid(alignment: .topLeading, horizontalSpacing: Theme.Space.m, verticalSpacing: Theme.Space.s) {
            GridRow {
                ForEach(0..<width, id: \.self) { i in MD(cell(header, i)).fontWeight(.semibold) }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(0..<width, id: \.self) { i in MD(cell(row, i)).fixedSize(horizontal: false, vertical: true) }
                }
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Color.secondary.opacity(0.08)))
    }

    private func cell(_ row: [String], _ i: Int) -> String { i < row.count ? row[i] : "" }
}


/// The sections of an issue written with the house template: Context, Goal, Steps, Watch out, QA, and the rest.
struct IssueSections {
    struct Item: Hashable { let text: String; let done: Bool }

    var context: String = ""
    var goal: String = ""
    var steps: [Item] = []
    var watchOut: String = ""
    var qa: [Item] = []
    /// Any other section, kept in order: title and raw Markdown.
    var other: [(title: String, body: String)] = []

    init(_ description: String) {
        var current = "", lines: [String] = [], folded = false
        func flush() {
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            defer { lines = [] }
            guard !body.isEmpty || !current.isEmpty else { return }
            switch Self.kind(of: current) {
            case "context": context = [context, body].filter { !$0.isEmpty }.joined(separator: "\n")
            case "goal": goal = [goal, body].filter { !$0.isEmpty }.joined(separator: "\n")
            case "steps": steps += Self.items(body)
            case "watch": watchOut = [watchOut, body].filter { !$0.isEmpty }.joined(separator: "\n")
            case "qa": qa += Self.items(body)
            default: if !body.isEmpty { other.append((current, body)) }
            }
        }
        for raw in description.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("+++") {
                if folded { folded = false; flush(); current = "" }
                else { flush(); folded = true; current = line.dropFirst(3).trimmingCharacters(in: .whitespaces) }
                continue
            }
            if !folded, line.hasPrefix("## ") { flush(); current = String(line.dropFirst(3)); continue }
            lines.append(raw)
        }
        flush()
    }

    /// Headings people actually write, mapped to the template's sections.
    static func kind(of heading: String) -> String {
        let h = heading.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " :"))
        let map: [String: [String]] = [
            "context": ["", "context", "background", "problem", "why", "description", "summary"],
            "goal": ["goal", "goals", "outcome", "objective"],
            "steps": ["steps", "actions", "plan", "tasks", "to do", "todo", "next steps"],
            "watch": ["watch out", "gotchas", "risks", "caveats", "notes"],
            "qa": ["qa", "acceptance criteria", "definition of done", "done when", "how to test", "testing", "test plan"],
        ]
        return map.first { $0.value.contains(h) }?.key ?? "other"
    }

    /// Checklist items from bullets, checkboxes or a numbered list. A plain paragraph line becomes an item too,
    /// so nothing written under Steps or QA is ever dropped.
    static func items(_ body: String) -> [Item] {
        body.components(separatedBy: "\n").compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            if let r = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) { line.removeSubrange(r); line = "- " + line }
            for (prefix, done) in [("- [ ] ", false), ("* [ ] ", false), ("- [x] ", true), ("* [x] ", true), ("- [X] ", true), ("- ", false), ("* ", false)]
            where line.hasPrefix(prefix) { return Item(text: String(line.dropFirst(prefix.count)), done: done) }
            return Item(text: line, done: false)
        }
    }
}
