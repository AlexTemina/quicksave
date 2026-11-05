import SwiftUI

/// Inline Markdown from Linear (bold, italic, `code`, links), rendered as a SwiftUI Text. Falls back to plain text.
struct MD: View {
    let source: String
    init(_ source: String) { self.source = source }

    var body: some View {
        Text(Self.attributed(source))
            .tint(.accentColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func attributed(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var text = (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
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
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.blocks(source).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let t): MD(t).font(.headline).padding(.top, 6)
                case .bullet(let mark, let t, let indent):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(mark).foregroundStyle(.secondary)
                        MD(t)
                    }.padding(.leading, CGFloat(indent) * 14)
                case .code(let t):
                    Text(t).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                case .folded(let t): Label(t, systemImage: "chevron.right").font(.caption).foregroundStyle(.secondary)
                case .paragraph(let t): MD(t)
                }
            }
        }
        .textSelection(.enabled)
    }

    enum Block { case heading(String), bullet(String, String, Int), code(String), folded(String), paragraph(String) }

    static func blocks(_ s: String) -> [Block] {
        var out: [Block] = [], code: [String]? = nil, folded = false
        for raw in s.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
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
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        return out
    }
}
