import Foundation

/// Someone asked him something by name: a mention in a GitHub discussion, pull request or issue, in Linear, Slack,
/// mail or Notion. The tab "Asked of me" lists them with whether he already answered at the source, and the card
/// that follows each one up. See docs/asks.md.
struct Ask: Identifiable, Codable, Hashable {
    /// Stable per source item: "gh:<url>", "linear:<comment or issue>", "agent:<link>".
    let id: String
    /// A `CardOrigin` raw value.
    let origin: String
    let who: String
    /// Where: the discussion's or pull request's title, the Slack channel, the mail's subject.
    let place: String
    /// What was asked, short.
    let text: String
    let url: String
    /// ISO 8601: when he was asked.
    let when: String
    /// The deadline the person set, in their words ("close this discussion by Wed, 18 Nov EOD").
    var deadline: String? = nil
    /// He wrote at the source after being asked.
    var answered: Bool = false
    /// A Linear issue it is about (a mention in Linear), which is then its own card when it is his.
    var issue: String? = nil

    var cardOrigin: CardOrigin { CardOrigin(rawValue: origin) ?? .linear }
    var date: Date? { QSDate.parse(when) }

    /// The number of a GitHub discussion, pull request or issue, as cards name it ("#35599").
    var githubNumber: String? {
        guard url.contains("github.com") else { return nil }
        let re = try! NSRegularExpression(pattern: #"/(?:discussions|pull|issues)/(\d+)"#)
        let ns = url as NSString
        return re.firstMatch(in: url, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    /// The URL without anchors or queries, to find it inside a card's description.
    var baseURL: String {
        var u = url
        if let i = u.firstIndex(where: { $0 == "#" || $0 == "?" }) { u = String(u[..<i]) }
        return u
    }
}

/// A card that follows an ask up.
struct AskCard: Hashable {
    let identifier: String
    let title: String
    let url: String
    let stateName: String
    let stateType: String
    let kind: CardKind?
    var isOpen: Bool { !["completed", "canceled"].contains(stateType) }
}

enum Asks {
    static let window: TimeInterval = 14 * 86400

    // MARK: GitHub

    /// GitHub mentions of the last two weeks, with whether he wrote after the last mention.
    static func github() async throws -> [Ask] {
        guard let gh = GitHub.binary else { throw QuicksaveError.message("The gh command is not installed.") }
        let me = try await login(gh)
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-window))
        let data = try await ghRun(gh, ["api", "notifications?all=true&per_page=50&since=\(since)"])
        struct Note: Decodable {
            struct Subject: Decodable { let title: String; let url: String?; let type: String }
            struct Repo: Decodable { let full_name: String }
            let reason: String; let updated_at: String; let subject: Subject; let repository: Repo
        }
        let notes = (try? JSONDecoder().decode([Note].self, from: data)) ?? []
        var out: [Ask] = []
        for n in notes where n.reason == "mention" {
            guard let api = n.subject.url, let num = api.split(separator: "/").last.map(String.init) else { continue }
            let repo = n.repository.full_name
            switch n.subject.type {
            case "Discussion":
                if let a = try? await discussion(gh, repo: repo, number: num, title: n.subject.title, me: me) { out.append(a) }
            case "PullRequest", "Issue":
                if let a = try? await issueLike(gh, repo: repo, number: num, title: n.subject.title, me: me, pr: n.subject.type == "PullRequest") {
                    out.append(a)
                }
            default: continue
            }
        }
        return out
    }

    private static var cachedLogin: String?
    private static func login(_ gh: String) async throws -> String {
        if let cachedLogin { return cachedLogin }
        let l = String(data: try await ghRun(gh, ["api", "user", "-q", ".login"]), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        cachedLogin = l
        return l
    }

    private static func ghRun(_ gh: String, _ args: [String]) async throws -> Data {
        let r = try await Shell.run(gh, args)
        guard r.status == 0 else {
            throw QuicksaveError.message("GitHub: " + (String(data: r.err, encoding: .utf8) ?? "gh failed").prefix(200))
        }
        return r.out
    }

    /// One post in a thread: who wrote it, when, what, and its link.
    private struct Post { let author: String; let at: String; let body: String; let url: String }

    /// The last post that names him, and whether he wrote after it.
    private static func verdict(_ posts: [Post], me: String) -> (mention: Post, answered: Bool)? {
        let handle = "@" + me.lowercased()
        let sorted = posts.sorted { $0.at < $1.at }
        guard let mention = sorted.last(where: { $0.body.lowercased().contains(handle) && $0.author.lowercased() != me.lowercased() })
        else { return nil }
        let answered = sorted.contains { $0.author.lowercased() == me.lowercased() && $0.at > mention.at }
        return (mention, answered)
    }

    /// The line around his handle, so the row says what was asked, not the whole post.
    private static func excerpt(_ body: String, me: String) -> String {
        let lines = body.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let line = lines.first { $0.lowercased().contains("@" + me.lowercased()) } ?? lines.first ?? ""
        let clean = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        return clean.count > 240 ? String(clean.prefix(240)) + "…" : clean
    }

    /// The close date a framing discussion announces, in its own words.
    static func deadline(in raw: String) -> String? {
        // "close this discussion by:" with the date on the next line, often as a list: join them.
        let joiner = try! NSRegularExpression(pattern: #"\bby\b:?\**:?\s*\r?\n(?:\s*\r?\n)*\s*(?:\d+\.|[-*])?\s*"#)
        let body = joiner.stringByReplacingMatches(in: raw.replacingOccurrences(of: "**", with: ""),
                                                   range: NSRange(location: 0, length: (raw.replacingOccurrences(of: "**", with: "") as NSString).length), withTemplate: "by ")
        let re = try! NSRegularExpression(pattern: #"(?i)[^\n.]{0,40}\b(close|conclu\w*|decide|inputs?|answers?|feedback|reply)\b[^\n]{0,50}?\bby\b[^\n]{3,70}"#)
        let ns = body as NSString
        guard let m = re.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let t = ns.substring(with: m.range).replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return t.count > 100 ? String(t.prefix(100)) + "…" : t
    }

    private static func discussion(_ gh: String, repo: String, number: String, title: String, me: String) async throws -> Ask? {
        let parts = repo.split(separator: "/")
        guard parts.count == 2 else { return nil }
        let q = """
        query { repository(owner: "\(parts[0])", name: "\(parts[1])") { discussion(number: \(number)) {
          url body createdAt author { login }
          comments(last: 60) { nodes { url body createdAt author { login }
            replies(last: 40) { nodes { url body createdAt author { login } } } } } } } }
        """
        let data = try await ghRun(gh, ["api", "graphql", "-f", "query=\(q)"])
        struct A: Decodable { let login: String }
        struct C: Decodable { let url: String; let body: String; let createdAt: String; let author: A? }
        struct Cs: Decodable { let nodes: [CWithReplies] }
        struct Rs: Decodable { let nodes: [C] }
        struct CWithReplies: Decodable { let url: String; let body: String; let createdAt: String; let author: A?; let replies: Rs }
        struct D: Decodable { let url: String; let body: String; let createdAt: String; let author: A?; let comments: Cs }
        struct Env: Decodable { struct R: Decodable { struct Repo: Decodable { let discussion: D? }; let repository: Repo }; let data: R? }
        guard let d = try JSONDecoder().decode(Env.self, from: data).data?.repository.discussion else { return nil }
        var posts = [Post(author: d.author?.login ?? "", at: d.createdAt, body: d.body, url: d.url)]
        for c in d.comments.nodes {
            posts.append(Post(author: c.author?.login ?? "", at: c.createdAt, body: c.body, url: c.url))
            posts += c.replies.nodes.map { Post(author: $0.author?.login ?? "", at: $0.createdAt, body: $0.body, url: $0.url) }
        }
        guard let v = verdict(posts, me: me) else { return nil }
        // Named in the framing's LOCI only: the ask is the discussion itself, answered once he posts anything.
        return Ask(id: "gh:" + d.url, origin: CardOrigin.discussion.rawValue, who: v.mention.author, place: title,
                   text: excerpt(v.mention.body, me: me), url: v.mention.url, when: v.mention.at,
                   deadline: deadline(in: d.body), answered: v.answered)
    }

    private static func issueLike(_ gh: String, repo: String, number: String, title: String, me: String, pr: Bool) async throws -> Ask? {
        struct U: Decodable { let login: String }
        struct I: Decodable { let html_url: String; let body: String?; let created_at: String; let user: U? }
        struct C: Decodable { let html_url: String; let body: String?; let created_at: String; let user: U? }
        let issue = try JSONDecoder().decode(I.self, from: try await ghRun(gh, ["api", "repos/\(repo)/issues/\(number)"]))
        var posts = [Post(author: issue.user?.login ?? "", at: issue.created_at, body: issue.body ?? "", url: issue.html_url)]
        let comments = (try? JSONDecoder().decode([C].self, from: try await ghRun(gh, ["api", "repos/\(repo)/issues/\(number)/comments?per_page=100"]))) ?? []
        posts += comments.map { Post(author: $0.user?.login ?? "", at: $0.created_at, body: $0.body ?? "", url: $0.html_url) }
        if pr {
            let review = (try? JSONDecoder().decode([C].self, from: try await ghRun(gh, ["api", "repos/\(repo)/pulls/\(number)/comments?per_page=100"]))) ?? []
            posts += review.map { Post(author: $0.user?.login ?? "", at: $0.created_at, body: $0.body ?? "", url: $0.html_url) }
        }
        guard let v = verdict(posts, me: me) else { return nil }
        return Ask(id: "gh:" + issue.html_url, origin: (pr ? CardOrigin.pullRequest : .githubIssue).rawValue, who: v.mention.author,
                   place: title, text: excerpt(v.mention.body, me: me), url: v.mention.url, when: v.mention.at,
                   deadline: deadline(in: issue.body ?? ""), answered: v.answered)
    }

    // MARK: Linear

    /// Linear mentions of the last two weeks, with whether he commented on the issue afterwards.
    static func linear(key: String) async throws -> [Ask] {
        let q = """
        query { notifications(first: 100) { nodes { id type createdAt actor { name }
          ... on IssueNotification { issue { identifier title url description } comment { id body createdAt url } } } } }
        """
        struct Actor: Decodable { let name: String }
        struct Issue: Decodable { let identifier: String; let title: String; let url: String; let description: String? }
        struct Comment: Decodable { let id: String; let body: String; let createdAt: String; let url: String? }
        struct N: Decodable { let id: String; let type: String; let createdAt: String; let actor: Actor?; let issue: Issue?; let comment: Comment? }
        struct Env: Decodable { struct D: Decodable { struct Ns: Decodable { let nodes: [N] }; let notifications: Ns }; let data: D? }
        let env = try JSONDecoder().decode(Env.self, from: try await Linear.send(q, key: key))
        let cutoff = Date().addingTimeInterval(-window)
        let mentions = (env.data?.notifications.nodes ?? []).filter {
            ["issueMention", "issueCommentMention"].contains($0.type) && (QSDate.parse($0.createdAt) ?? .distantPast) > cutoff
        }
        var out: [Ask] = []
        var seen = Set<String>()
        for n in mentions {
            guard let issue = n.issue else { continue }
            let id = "linear:" + (n.comment?.id ?? issue.identifier)
            guard seen.insert(id).inserted else { continue }
            let at = n.comment?.createdAt ?? n.createdAt
            let answered = (try? await answeredInLinear(key: key, issue: issue.identifier, after: at)) ?? false
            let body = n.comment?.body ?? issue.description ?? ""
            let line = body.components(separatedBy: "\n").first { $0.contains("@") } ?? body.components(separatedBy: "\n").first ?? ""
            out.append(Ask(id: id, origin: CardOrigin.linear.rawValue, who: n.actor?.name ?? "Someone",
                           place: "\(issue.identifier) · \(issue.title)", text: String(line.prefix(240)),
                           url: n.comment?.url ?? issue.url, when: at, deadline: nil, answered: answered, issue: issue.identifier))
        }
        return out
    }

    private static func answeredInLinear(key: String, issue: String, after: String) async throws -> Bool {
        let q = "query { issue(id: \"\(issue)\") { comments(first: 100) { nodes { createdAt user { isMe } } } } }"
        struct U: Decodable { let isMe: Bool }
        struct C: Decodable { let createdAt: String; let user: U? }
        struct Env: Decodable { struct D: Decodable { struct I: Decodable { struct Cs: Decodable { let nodes: [C] }; let comments: Cs }; let issue: I? }; let data: D? }
        let env = try JSONDecoder().decode(Env.self, from: try await Linear.send(q, key: key))
        return (env.data?.issue?.comments.nodes ?? []).contains { $0.user?.isMe == true && $0.createdAt > after }
    }

    // MARK: Cards

    /// His TEMI cards of the last month, open or closed, with what they link to, to find the card of each ask.
    static func cards(key: String) async throws -> [(card: AskCard, text: String)] {
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30 * 86400))
        let q = """
        query { issues(first: 250, filter: { team: { key: { eq: "TEMI" } }, updatedAt: { gt: "\(since)" } }) {
          nodes { identifier title url description state { name type } labels { nodes { name } } attachments { nodes { url } } } } }
        """
        struct N: Decodable { let name: String }
        struct Ns: Decodable { let nodes: [N] }
        struct A: Decodable { let url: String }
        struct As: Decodable { let nodes: [A] }
        struct S: Decodable { let name: String; let type: String }
        struct I: Decodable { let identifier: String; let title: String; let url: String; let description: String?; let state: S; let labels: Ns?; let attachments: As? }
        struct Env: Decodable { struct D: Decodable { struct Is: Decodable { let nodes: [I] }; let issues: Is }; let data: D? }
        let env = try JSONDecoder().decode(Env.self, from: try await Linear.send(q, key: key))
        return (env.data?.issues.nodes ?? []).map { i in
            let labels = i.labels?.nodes.map(\.name) ?? []
            let card = AskCard(identifier: i.identifier, title: i.title, url: i.url, stateName: i.state.name, stateType: i.state.type,
                               kind: CardKind.of(labels: labels, title: i.title, identifier: i.identifier))
            let text = ([i.title, i.description ?? ""] + (i.attachments?.nodes.map(\.url) ?? [])).joined(separator: "\n").lowercased()
            return (card, text)
        }
    }

    /// The card that follows an ask up: one naming its link, or its discussion number in the title ("#35599"), or,
    /// for a mention in Linear, one naming that issue. An open card wins over a closed one.
    static func card(for ask: Ask, in cards: [(card: AskCard, text: String)]) -> AskCard? {
        let base = ask.baseURL.lowercased()
        let matches = cards.filter { c in
            if !base.isEmpty, c.text.contains(base) { return true }
            if let n = ask.githubNumber, ask.cardOrigin == .discussion,
               c.text.contains("#\(n)") || c.text.contains("discussions/\(n)") { return true }
            if let issue = ask.issue?.lowercased(), c.text.contains(issue) { return true }
            return false
        }
        // Best first: open, then the card whose title names it ("Read and answer #35599"), then one whose kind says
        // someone waits, over a card that only links it (a plan review, say).
        func rank(_ c: (card: AskCard, text: String)) -> (Int, Int, Int) {
            let named = ask.githubNumber.map { c.card.title.contains("#\($0)") } ?? (ask.issue.map { c.card.title.contains($0) } ?? false)
            return (c.card.isOpen ? 0 : 1, named ? 0 : 1, c.card.kind?.someoneWaits == true ? 0 : 1)
        }
        return matches.min { rank($0) < rank($1) }?.card
    }

    // MARK: Creating a card

    /// Files a TEMI card for an ask, in the auditor's shape, and returns its code. One of the writes the app makes.
    static func createCard(for ask: Ask) async throws -> String {
        let kind: CardKind = ask.cardOrigin == .pullRequest && ask.text.lowercased().contains("review") ? .review : .answer
        let source: String = {
            switch ask.cardOrigin {
            case .discussion: return "#\(ask.githubNumber ?? "")"
            case .pullRequest: return "PR #\(ask.githubNumber ?? "")"
            default: return ask.cardOrigin.rawValue.lowercased()
            }
        }()
        let title = String("\(kind == .review ? "Review" : "Read and answer") \(source) — \(ask.place)".prefix(120))
        let body = """
        \(ask.who) asked him in \(ask.cardOrigin == .linear ? "Linear" : "a \(ask.cardOrigin.rawValue.lowercased())") on \(QSDate.friendly(String(ask.when.prefix(10)))).

        * Ask: \(ask.text)
        \(ask.deadline.map { "* Deadline they set: \($0)\n" } ?? "")* Source: [\(ask.place)](\(ask.url))
        \(ask.cardOrigin == .discussion ? "* Start with `/discussion-copilot \(ask.githubNumber ?? "")`.\n" : "")
        Filed from Quicksave's Asked of me.
        """
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("quicksave-ask-\(UUID().uuidString).md")
        try body.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        // Due today: someone is waiting. The morning plan and the inbox's expired cards move it from there.
        let args = ["linear", "create", "--team", "TEMI", "--title", title, "--body-file", file.path, "--assignee", "me",
                    "--state", "Todo", "--priority", "high", "--due-date", InboxWrites.today(), "--label", kind.rawValue, "--json"]
        let r = try await Shell.run(Orca.binary, args)
        let text = String(data: r.out, encoding: .utf8) ?? ""
        let re = try! NSRegularExpression(pattern: #"\bTEMI-\d+\b"#)
        let ns = text as NSString
        if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) { return ns.substring(with: m.range) }
        let said = (try? JSONSerialization.jsonObject(with: r.out) as? [String: Any]).flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
        throw QuicksaveError.message(said ?? "Linear did not confirm the new card. \(String(data: r.err, encoding: .utf8)?.prefix(200) ?? "")")
    }

    // MARK: Slack, mail and Notion

    /// Looks for asks in Slack, Gmail and Notion since a moment. Reads only.
    static func agentJob(since: Date, known: [Ask]) -> AgentJob {
        let open = known.filter { !$0.answered }.map { "- \($0.url)" }.joined(separator: "\n")
        return AgentJob(
            name: "asked of me",
            directory: NSTemporaryDirectory(),
            prompt: """
            Find what people asked Alejandro Ruiz Temina (Slack @alextemina, mail alex.temina@alan.eu) directly, by name, since \(ISO8601DateFormatter().string(from: since)). Today is \(Morning.todayLong).
            - Slack: messages that mention him, and direct messages to him, that ask him something or wait on him. Search with the Slack search tools ("to:me", his mention, "@alextemina"); read the thread to know if he already replied after.
            - Gmail: threads from a person (not newsletters, notifications, calendar invites or automated mail) that ask him something. Read the thread to know if he replied after.
            - Notion: comments or pages that mention him and ask something. Best effort: skip it if the tools cannot find mentions.
            Leave out messages he wrote, pure FYIs, thanks, and bots. Also check these asks still open from before, and say whether he has answered them now:
            \(open.isEmpty ? "(none)" : open)
            For each ask: origin (Slack, Mail or Notion), who (the person's name), place (#channel, "DM", the mail subject or the page title), text (what they ask him, one sentence in English, at most 200 characters), url (the permalink), when (ISO 8601, when they asked), deadline (a date or time they set, in their words, else empty), answered (true when he wrote in that thread or replied after).
            The tools are deferred: find them first with ToolSearch. Read only: never send, draft, react or comment.
            """,
            model: "claude-haiku-5-5",
            allowed: ["ToolSearch",
                      "mcp__claude_ai_Slack__slack_search_public_and_private", "mcp__claude_ai_Slack__slack_search_public",
                      "mcp__claude_ai_Slack__slack_read_thread", "mcp__claude_ai_Slack__slack_read_channel",
                      "mcp__claude_ai_Slack__slack_search_users", "mcp__claude_ai_Slack__slack_read_user_profile",
                      "mcp__claude_ai_Gmail__search_threads", "mcp__claude_ai_Gmail__get_thread", "mcp__claude_ai_Gmail__get_message",
                      "mcp__claude_ai_Notion__notion-search", "mcp__claude_ai_Notion__notion-fetch", "mcp__claude_ai_Notion__notion-get-comments"],
            denied: Morning.neverPost + ["mcp__claude_ai_Slack__slack_send_message_draft", "mcp__claude_ai_Gmail__create_draft",
                                         "mcp__claude_ai_Notion__notion-create-comment"],
            schema: """
            {"type":"object","properties":{"asks":{"type":"array","items":{"type":"object","properties":{"origin":{"type":"string","enum":["Slack","Mail","Notion"]},"who":{"type":"string"},"place":{"type":"string"},"text":{"type":"string"},"url":{"type":"string"},"when":{"type":"string"},"deadline":{"type":"string"},"answered":{"type":"boolean"}},"required":["origin","who","place","text","url","when","answered"]}}},"required":["asks"]}
            """,
            maxTurns: 40)
    }

    struct AgentResult: Decodable {
        struct Item: Decodable {
            let origin: String; let who: String; let place: String; let text: String; let url: String; let when: String
            let deadline: String?; let answered: Bool
        }
        let asks: [Item]
    }

    static func fromAgent(_ i: AgentResult.Item) -> Ask {
        let origin: CardOrigin = i.origin == "Mail" ? .mail : i.origin == "Notion" ? .notion : .slack
        return Ask(id: "agent:" + i.url, origin: origin.rawValue, who: i.who, place: i.place, text: i.text, url: i.url, when: i.when,
                   deadline: (i.deadline ?? "").isEmpty ? nil : i.deadline, answered: i.answered)
    }
}
