import SwiftUI

/// What a card asks of him. Lives in Linear as a child of the `Kind` label group (TEMI, one per issue); the auditor
/// sets it when it files a card. Issues without the label (every ES issue) get it from their title. See docs/board.md.
enum CardKind: String, CaseIterable, Identifiable {
    case answer = "Answer", unblock = "Unblock", review = "Review", decide = "Decide", ask = "Ask", chase = "Chase"
    case build = "Build", fix = "Fix", write = "Write", prepare = "Prepare", interview = "Interview", people = "People"
    case admin = "Admin", read = "Read", track = "Track"
    var id: String { rawValue }

    /// Someone is waiting on him: these go first in the plan after anything breaking.
    var someoneWaits: Bool { [.answer, .unblock, .review].contains(self) }

    var color: Color { Theme.Palette.kind(self) }

    var icon: String {
        switch self {
        case .answer: return "bubble.left.and.text.bubble.right"
        case .unblock: return "lock.open"
        case .review: return "eye"
        case .decide: return "arrow.triangle.branch"
        case .ask: return "questionmark.bubble"
        case .chase: return "arrow.uturn.forward"
        case .build: return "hammer"
        case .fix: return "wrench.and.screwdriver"
        case .write: return "pencil.line"
        case .prepare: return "calendar.badge.clock"
        case .interview: return "person.crop.rectangle"
        case .people: return "person.2"
        case .admin: return "tray"
        case .read: return "book"
        case .track: return "binoculars"
        }
    }

    /// The kind from an issue's labels, else from its title, else Build for an ES issue (engineering work by default).
    static func of(labels: [String], title: String, identifier: String) -> CardKind? {
        for l in labels { if let k = CardKind(rawValue: l) { return k } }
        if labels.contains("collectible") { return .read }
        let t = title.lowercased()
        let rules: [(String, CardKind)] = [
            ("read and answer", .answer), ("answer ", .answer), ("reply ", .answer), ("respond ", .answer),
            ("read:", .read), ("watch:", .read),
            ("review ", .review), ("decide ", .decide), ("pick ", .decide), ("choose ", .decide),
            ("ask ", .ask), ("chase ", .chase), ("follow up", .chase), ("remind ", .chase),
            ("grant ", .unblock), ("give access", .unblock), ("approve ", .unblock),
            ("fix ", .fix), ("investigate ", .fix), ("check why", .fix),
            ("write ", .write), ("draft ", .write), ("announce", .write),
            ("prepare ", .prepare), ("show ", .prepare), ("demo ", .prepare),
            ("screening", .interview), ("interview", .interview), ("scorecard", .interview),
            ("1:1", .people), ("peer review", .people), ("feedback", .people),
            ("course", .admin), ("survey", .admin), ("expense", .admin), ("book ", .admin),
        ]
        for (prefix, k) in rules where t.hasPrefix(prefix) || (prefix.count > 6 && t.contains(prefix)) { return k }
        return identifier.hasPrefix("ES-") ? .build : nil
    }
}

/// Where a card comes from: the first link in its description or its attachments (the auditor attaches the source)
/// that points somewhere a person asked him something.
/// Read from the description each time; nothing is stored.
enum CardOrigin: String {
    case discussion = "Discussion", pullRequest = "Pull request", githubIssue = "GitHub issue", slack = "Slack", mail = "Mail"
    case notion = "Notion", meeting = "Meeting", linear = "Linear"

    var icon: String {
        switch self {
        case .discussion: return "bubble.left.and.bubble.right"
        case .pullRequest: return Theme.Icon.pullRequest
        case .githubIssue: return "exclamationmark.circle"
        case .slack: return "number"
        case .mail: return "envelope"
        case .notion: return "doc.text"
        case .meeting: return "mic"
        case .linear: return "square.stack"
        }
    }

    /// Its own pull requests (attached by GitHub) are not where an engineering card comes from, so a pull request only
    /// counts as the origin of a Review.
    static func of(description: String, kind: CardKind?) -> CardOrigin {
        let d = description.lowercased()
        let order: [(String, CardOrigin)] = [
            ("github.com/alan-eu/topics/discussions/", .discussion), ("/discussions/", .discussion),
            ("slack.com/archives", .slack), ("mail.google.com", .mail), ("notion.so/", .notion), ("notion.com/", .notion),
            ("wisprflow", .meeting),
        ]
        var best: (Int, CardOrigin)?
        for (needle, origin) in order {
            if let r = d.range(of: needle) {
                let at = d.distance(from: d.startIndex, to: r.lowerBound)
                if best == nil || at < best!.0 { best = (at, origin) }
            }
        }
        if let best { return best.1 }
        if d.contains("read and answer #") { return .discussion }
        if kind == .review, d.contains("/pull/") { return .pullRequest }
        if d.contains("github.com/"), d.contains("/issues/") { return .githubIssue }
        return .linear
    }
}

/// The card's kind and where it comes from, as one small tag in its color at the bottom right of the card: "💬 Answer".
struct QSKindTag: View {
    let kind: CardKind
    var origin: CardOrigin = .linear

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if origin != .linear {
                Image(systemName: origin.icon).foregroundStyle(Theme.Palette.textSecondary)
            }
            Label(kind.rawValue, systemImage: kind.icon).foregroundStyle(kind.color)
        }
        .font(Theme.Text.micro)
        .padding(.horizontal, Theme.Space.s - 2).padding(.vertical, 2)
        .background(Capsule().fill(Theme.Palette.pill(kind.color)))
        .help(origin == .linear ? kind.rawValue : "\(kind.rawValue), from a \(origin.rawValue.lowercased())")
    }
}
