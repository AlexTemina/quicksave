import AppKit
import SwiftUI

/// Hover cards: resting the pointer on any link shows, after a moment, a small card with what it is. Linear issues
/// and GitHub pull requests are read through their APIs, any other web page through its title and summary.
/// Slack links get no card yet: reading Slack fast needs a token the app does not have. Each link is read once and kept for the session. See docs/design-system.md.

enum LinkTarget: Hashable {
    case linear(String)
    case pullRequest(repo: String, number: Int)
    case web(URL)

    /// Every web link gets a card, except Slack's.
    init?(_ url: URL) {
        let parts = url.path.split(separator: "/").map(String.init)
        if url.host?.hasSuffix("linear.app") == true, let i = parts.firstIndex(of: "issue"), i + 1 < parts.count {
            self = .linear(parts[i + 1].uppercased())
        } else if url.host == "github.com", parts.count >= 4, parts[2] == "pull", let n = Int(parts[3]) {
            self = .pullRequest(repo: "\(parts[0])/\(parts[1])", number: n)
        } else if ["http", "https"].contains(url.scheme ?? ""), let host = url.host, !host.hasSuffix("slack.com") {
            self = .web(url)
        } else {
            return nil
        }
    }
}

struct LinkPreviewData {
    let source: String
    let code: String
    let title: String
    /// A state with its color, when the thing has one.
    let state: (name: String, color: Color)?
    /// Short facts: icon and text.
    let facts: [(icon: String, text: String, color: Color?)]
    let excerpt: String
}

@MainActor
final class LinkPreviews: ObservableObject {
    static let shared = LinkPreviews()
    enum Entry { case loading, ready(LinkPreviewData), failed(String) }
    @Published private(set) var entries: [LinkTarget: Entry] = [:]

    func load(_ target: LinkTarget) {
        if let e = entries[target], case .failed = e {} else if entries[target] != nil { return }
        entries[target] = .loading
        Task {
            do { entries[target] = .ready(try await fetch(target)) }
            catch { entries[target] = .failed(error.localizedDescription) }
        }
    }

    private func fetch(_ target: LinkTarget) async throws -> LinkPreviewData {
        switch target {
        case .linear(let id):
            guard let key = Database.shared.secret("linearApiKey") else { throw QuicksaveError.message("No Linear API key in Settings.") }
            guard let i = try await Linear.issuePreview(key: key, id: id) else { throw QuicksaveError.message("Linear does not know \(id).") }
            var facts: [(String, String, Color?)] = []
            facts.append(("person", i.assignee?.name ?? "Unassigned", nil))
            if let due = i.dueDate { facts.append((Theme.Icon.due, QSDate.friendly(due), nil)) }
            if let p = i.priorityLabel, p != "No priority" { facts.append(("flag", p, nil)) }
            if let project = i.project?.name { facts.append(("folder", project, nil)) }
            let labels = (i.labels?.nodes ?? []).map(\.name)
            if !labels.isEmpty { facts.append(("tag", labels.joined(separator: ", "), nil)) }
            return LinkPreviewData(source: "Linear", code: i.identifier, title: i.title,
                                   state: (i.state.name, Color(hex: i.state.color ?? "#95a2b3")), facts: facts,
                                   excerpt: Self.excerpt(i.description ?? ""))
        case .pullRequest(let repo, let number):
            guard let p = await GitHub.prPreview(repo: repo, number: number) else {
                throw QuicksaveError.message("GitHub did not answer for #\(number). Is gh logged in?")
            }
            let state = p.isDraft && p.state == "OPEN" ? "Draft" : p.state.capitalized
            let color: Color = switch state {
            case "Merged": Theme.Palette.prMerged
            case "Closed": Theme.Palette.prClosed
            case "Draft": Theme.Palette.prDraft
            default: p.ci == .failing ? Theme.Palette.prFailing : Theme.Palette.prOpen
            }
            var facts: [(String, String, Color?)] = []
            if let a = p.author?.login { facts.append(("person", a, nil)) }
            switch p.ci {
            case .passing: facts.append(("checkmark.circle.fill", "CI passing", Theme.Palette.prOpen))
            case .failing: facts.append(("xmark.octagon.fill", "CI failing", Theme.Palette.prFailing))
            case .running: facts.append(("clock", "CI running", nil))
            case .none: break
            }
            switch p.reviewDecision {
            case "APPROVED": facts.append(("hand.thumbsup.fill", "Approved", Theme.Palette.prOpen))
            case "CHANGES_REQUESTED": facts.append(("exclamationmark.bubble.fill", "Changes requested", Theme.Palette.warning))
            case "REVIEW_REQUIRED": facts.append(("eye", "Review required", nil))
            default: break
            }
            facts.append(("plusminus", "+\(p.additions) −\(p.deletions) in \(p.changedFiles) file\(p.changedFiles == 1 ? "" : "s")", nil))
            return LinkPreviewData(source: repo, code: "#\(p.number)", title: p.title, state: (state, color),
                                   facts: facts, excerpt: Self.excerpt(p.body ?? ""))
        case .web(let url):
            return try await WebPage.preview(url)
        }
    }

    /// The start of a description: no images, no folded sections, a few lines at most.
    static func excerpt(_ text: String) -> String {
        var out: [String] = []
        var folded = false
        var length = 0
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("+++") || line.hasPrefix("<details") || line.hasPrefix("</details") { folded.toggle(); continue }
            if folded || line.isEmpty || line.hasPrefix("![") || line.hasPrefix("<!--") { continue }
            out.append(raw)
            length += line.count
            if out.count >= 7 || length > 420 { out.append("…"); break }
        }
        return out.joined(separator: "\n")
    }
}

/// The hover card itself.
struct LinkPreviewCard: View {
    let target: LinkTarget
    @ObservedObject private var previews = LinkPreviews.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            switch previews.entries[target] {
            case .ready(let d):
                HStack(spacing: Theme.Space.s) {
                    Text(d.code).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                    if let state = d.state { QSPill(text: state.name, color: state.color) }
                    Spacer()
                    Text(d.source).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary)
                }
                Text(d.title).font(Theme.Text.cardTitle).fixedSize(horizontal: false, vertical: true)
                FlowFacts(facts: d.facts)
                if !d.excerpt.isEmpty {
                    Divider().padding(.vertical, 2)
                    MarkdownBlock(d.excerpt).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                }
            case .failed(let why):
                QSNote(text: why, icon: "exclamationmark.triangle", warning: true)
            default:
                HStack(spacing: Theme.Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Loading…").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .environment(\.linkPreviewsEnabled, false)
        .padding(Theme.Space.l)
        .frame(width: Theme.Size.hoverCardWidth, alignment: .leading)
    }
}

private struct FlowFacts: View {
    let facts: [(icon: String, text: String, color: Color?)]
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                Label(f.text, systemImage: f.icon).font(Theme.Text.meta)
                    .foregroundStyle(f.color ?? Theme.Palette.textSecondary)
            }
        }
    }
}

/// A link the pointer is on, and where it sits inside the view (nil: the whole view).
struct HoveredLink: Equatable {
    let target: LinkTarget
    let rect: CGRect?
}

extension EnvironmentValues {
    /// Off inside a hover card, so a card never opens another card.
    @Entry var linkPreviewsEnabled = true
}

/// Shows the card for the link under the pointer, after a short rest, and hides it a moment after the pointer
/// leaves, unless the pointer went onto the card.
struct LinkPreviewHost: ViewModifier {
    let hovered: HoveredLink?
    @State private var shown: HoveredLink?
    @State private var timer: Task<Void, Never>?
    @State private var overCard = false

    func body(content: Content) -> some View {
        content
            .onChange(of: hovered) { schedule() }
            .popover(isPresented: Binding(get: { shown != nil }, set: { if !$0 { shown = nil } }),
                     attachmentAnchor: shown?.rect.map { .rect(.rect($0)) } ?? .rect(.bounds), arrowEdge: .bottom) {
                if let shown {
                    LinkPreviewCard(target: shown.target)
                        .onHover { overCard = $0; if !$0 { schedule() } }
                }
            }
    }

    private func schedule() {
        timer?.cancel()
        if let hovered {
            LinkPreviews.shared.load(hovered.target)
            if shown?.target == hovered.target { return }
            timer = Task { @MainActor in
                try? await Task.sleep(for: Theme.Motion.hoverCardDelay)
                if !Task.isCancelled { shown = hovered }
            }
        } else if shown != nil {
            timer = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled && !overCard && self.hovered == nil { shown = nil }
            }
        }
    }
}

private struct LinkPreviewOnHover: ViewModifier {
    let target: LinkTarget?
    @State private var hovered: HoveredLink?
    @Environment(\.linkPreviewsEnabled) private var enabled

    func body(content: Content) -> some View {
        if let target, enabled {
            content
                .onHover { hovered = $0 ? HoveredLink(target: target, rect: nil) : nil }
                .modifier(LinkPreviewHost(hovered: hovered))
        } else {
            content
        }
    }
}

extension View {
    /// A hover card for this whole view, when the link is a Linear issue or a GitHub pull request.
    func linkPreview(_ url: URL?) -> some View { modifier(LinkPreviewOnHover(target: url.flatMap(LinkTarget.init))) }
}

// MARK: Links inside text

/// Marks the part of a text that is a link, so the renderer can tell where each link sits.
struct LinkAttribute: TextAttribute { let target: LinkTarget }

/// Where each link of a text was drawn, in the text's own coordinates.
final class LinkRects: @unchecked Sendable { var rects: [(LinkTarget, CGRect)] = [] }

/// Draws the text as it is, noting the frame of every run marked as a link.
struct LinkTrackingRenderer: TextRenderer {
    let box: LinkRects
    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var found: [(LinkTarget, CGRect)] = []
        for line in layout {
            for run in line {
                if let a = run[LinkAttribute.self] { found.append((a.target, run.typographicBounds.rect)) }
            }
            ctx.draw(line)
        }
        box.rects = found
    }
}

// MARK: Any web page

/// The title and summary a page gives of itself. Wikipedia has its own summary service, which says more.
enum WebPage {
    static func preview(_ url: URL) async throws -> LinkPreviewData {
        let host = (url.host ?? "").replacingOccurrences(of: "www.", with: "")
        let parts = url.path.split(separator: "/").map(String.init)
        if host.hasSuffix("wikipedia.org"), parts.count >= 2, parts[0] == "wiki",
           let summary = try? await wikipedia(host: url.host ?? host, title: parts[1]) {
            return summary
        }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Mozilla/5.0 (Macintosh) Quicksave", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(decoding: data.prefix(400_000), as: UTF8.self)
        let title = meta(html, "og:title") ?? tag(html, "title") ?? url.absoluteString
        let summary = meta(html, "og:description") ?? meta(html, "description") ?? ""
        let site = meta(html, "og:site_name") ?? host
        return LinkPreviewData(source: site, code: host, title: title, state: nil, facts: [],
                               excerpt: summary.count > 420 ? String(summary.prefix(420)) + "…" : summary)
    }

    private static func wikipedia(host: String, title: String) async throws -> LinkPreviewData? {
        guard let api = URL(string: "https://\(host)/api/rest_v1/page/summary/\(title)") else { return nil }
        let (data, _) = try await URLSession.shared.data(from: api)
        struct Summary: Decodable { let title: String; let description: String?; let extract: String? }
        let s = try JSONDecoder().decode(Summary.self, from: data)
        let extract = s.extract ?? ""
        return LinkPreviewData(source: "Wikipedia", code: host, title: s.title, state: nil,
                               facts: s.description.map { [("info.circle", $0, nil)] } ?? [],
                               excerpt: extract.count > 420 ? String(extract.prefix(420)) + "…" : extract)
    }

    /// The content of a meta tag, by its property or name, in either attribute order.
    private static func meta(_ html: String, _ key: String) -> String? {
        let k = NSRegularExpression.escapedPattern(for: key)
        for pattern in [#"<meta[^>]+(?:property|name)=["']\#(k)["'][^>]*content=["']([^"']*)["']"#,
                        #"<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']\#(k)["']"#] {
            if let v = first(html, pattern), !v.isEmpty { return v }
        }
        return nil
    }

    private static func tag(_ html: String, _ name: String) -> String? {
        first(html, "<\(name)[^>]*>([^<]*)</\(name)>")
    }

    private static func first(_ html: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return decode(String(html[r])).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decode(_ s: String) -> String {
        var out = s
        for (entity, char) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }
}
