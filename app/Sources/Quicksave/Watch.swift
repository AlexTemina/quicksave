import Foundation

/// Cards in "Pending for inputs" wait for someone else. Every ten minutes the app looks, by itself and without Claude,
/// at what could answer them: the issue's Linear comments, its pull requests (reviews, comments, CI, merged, conflicts)
/// and the GitHub discussions it links. Slack threads it links are read every thirty minutes by a small agent, the only
/// part that costs tokens. What is new wakes the card's agent; with no agent to wake, the card shows it.
/// See docs/board.md, "Watching what waits".
enum Watch {
    static let interval: TimeInterval = 600
    /// Slack is read on one check out of this many.
    static let slackEvery = 3

    struct Event: Codable, Hashable {
        let when: String
        let source: String
        let what: String
        /// CI turned red on a pull request: on a card in review, its agent is asked to fix it.
        var ciFailed: Bool? = nil
        /// Worth showing on the card but not worth an agent's turn, like CI turning green (ES-12992 was woken for it, 11-nov).
        var quiet: Bool? = nil
        var line: String { "\(source): \(what)" }
    }

    /// What the app found new on a card, kept until he says he has seen it.
    struct News: Codable {
        var events: [Event]
        var at: Date
        /// "woken", "agent busy", "no agent".
        var agent: String
    }

    /// Where a card was last looked at: events after `since` are new. The first look only sets it.
    struct Seen: Codable {
        var since: String
        var slackSince: String?
        /// By pull request: "state ci mergeable" when last read, to tell when it changes.
        var prs: [String: String] = [:]
        /// By pull request: how many times its agent was asked to fix the CI. It stops at `maxCIFixes`.
        var ciFixes: [String: Int]? = nil
        /// By source ("linear", "pr <repo>#<n>", "discussion <repo>#<n>"): read up to here. Moved only when read.
        var sources: [String: String]? = nil
    }

    /// The last look at a card, for the line it shows.
    struct Status {
        let at: Date
        let failed: [String]
        /// How many places it read: the issue, each pull request and discussion, and Slack.
        let sources: Int
        let slackLinked: Bool
    }

    static let maxCIFixes = 3

    struct Links {
        var discussions: [(repo: String, number: Int)] = []
        var slack: [String] = []
        var prs: [(repo: String, number: Int)] = []
    }

    static func now() -> String { ISO8601DateFormatter().string(from: Date()) }

    static func after(_ iso: String, _ since: String) -> Bool {
        guard let a = QSDate.parse(iso), let b = QSDate.parse(since) else { return false }
        return a > b
    }

    static func latest(_ a: String, _ b: String) -> String { after(a, b) ? a : b }

    /// Discussions, pull requests and Slack threads named in any of these texts.
    static func links(in texts: [String]) -> Links {
        var out = Links()
        let all = texts.joined(separator: "\n") as NSString
        func each(_ pattern: String, _ body: (NSTextCheckingResult) -> Void) {
            let re = try! NSRegularExpression(pattern: pattern)
            re.enumerateMatches(in: all as String, range: NSRange(location: 0, length: all.length)) { m, _, _ in m.map(body) }
        }
        each(#"github\.com/([\w.-]+/[\w.-]+)/discussions/(\d+)"#) { m in
            let repo = all.substring(with: m.range(at: 1)), n = Int(all.substring(with: m.range(at: 2))) ?? 0
            if !out.discussions.contains(where: { $0.repo == repo && $0.number == n }) { out.discussions.append((repo, n)) }
        }
        each(#"github\.com/([\w.-]+/[\w.-]+)/pull/(\d+)"#) { m in
            let repo = all.substring(with: m.range(at: 1)), n = Int(all.substring(with: m.range(at: 2))) ?? 0
            if !out.prs.contains(where: { $0.repo == repo && $0.number == n }) { out.prs.append((repo, n)) }
        }
        each(#"https://[\w-]+\.slack\.com/archives/[A-Z0-9]+/p\d+[^\s)>\]|]*"#) { m in
            let url = all.substring(with: m.range)
            if !out.slack.contains(url) { out.slack.append(url) }
        }
        return out
    }

    static func isBot(_ login: String) -> Bool {
        let l = login.lowercased()
        // Integrations that comment on every pull request (linear-code, alan-pr-check on 11-nov) are not people answering.
        return l.contains("bot") || l.hasPrefix("linear") || l.hasSuffix("-check")
            || ["github-actions", "codecov", "sonarcloud", "vercel", "copilot"].contains(l)
    }

    // MARK: GitHub

    private static var me: String?

    /// His GitHub login, so his own comments are never news.
    static func myLogin() async -> String {
        if let me { return me }
        guard let gh = GitHub.binary, let r = try? await Shell.run(gh, ["api", "user", "-q", ".login"]), r.status == 0 else { return "" }
        let login = String(data: r.out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        me = login
        return login
    }

    /// What is new on a pull request since `since`, and how it stands now ("state ci mergeable").
    /// On a card in review, a CI already red at the first look counts too: it needs fixing all the same.
    static func pullRequest(repo: String, number: Int, since: String, before: String?, inReview: Bool = false) async -> (events: [Event], now: String)? {
        guard let gh = GitHub.binary,
              let r = try? await Shell.run(gh, ["pr", "view", "\(number)", "--repo", repo, "--json", "state,isDraft,mergeable,reviews,comments,statusCheckRollup"]),
              r.status == 0 else { return nil }
        struct Author: Decodable { let login: String }
        struct Review: Decodable { let author: Author?; let state: String; let submittedAt: String?; let body: String? }
        struct Comment: Decodable { let author: Author?; let createdAt: String; let body: String? }
        struct Check: Decodable { let conclusion: String?; let status: String?; let state: String? }
        struct PR: Decodable {
            let state: String; let isDraft: Bool; let mergeable: String?
            let reviews: [Review]?; let comments: [Comment]?; let statusCheckRollup: [Check]?
        }
        guard let p = try? JSONDecoder().decode(PR.self, from: r.out) else { return nil }
        let me = await myLogin()
        let tag = "#\(number)"
        var events: [Event] = []
        for rv in p.reviews ?? [] {
            guard let at = rv.submittedAt, after(at, since), let who = rv.author?.login, who != me, !isBot(who) else { continue }
            let kind = ["APPROVED": "approved", "CHANGES_REQUESTED": "asked for changes", "COMMENTED": "reviewed"][rv.state] ?? rv.state.lowercased()
            events.append(Event(when: at, source: "GitHub \(tag)", what: "\(who) \(kind)" + snippet(rv.body)))
        }
        for c in p.comments ?? [] {
            guard after(c.createdAt, since), let who = c.author?.login, who != me, !isBot(who) else { continue }
            events.append(Event(when: c.createdAt, source: "GitHub \(tag)", what: "\(who) commented" + snippet(c.body)))
        }
        let results = (p.statusCheckRollup ?? []).map { ($0.conclusion ?? $0.state ?? $0.status ?? "").uppercased() }
        let ci: String
        if results.isEmpty { ci = "none" }
        else if results.contains(where: { ["FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE"].contains($0) }) { ci = "failing" }
        else if results.contains(where: { ["", "IN_PROGRESS", "QUEUED", "PENDING", "WAITING", "EXPECTED"].contains($0) }) { ci = "running" }
        else { ci = "passing" }
        let state = p.isDraft && p.state == "OPEN" ? "draft" : p.state.lowercased()
        let mergeable = (p.mergeable ?? "UNKNOWN").lowercased()
        let current = "\(state) \(ci) \(mergeable)"
        if before == nil, inReview, ci == "failing" {
            events.append(Event(when: now(), source: "GitHub \(tag)", what: "CI is failing", ciFailed: true))
        }
        if let before, before != current {
            let old = before.split(separator: " ").map(String.init)
            let stamp = now()
            if old.count == 3 {
                if old[0] != state, ["merged", "closed"].contains(state) { events.append(Event(when: stamp, source: "GitHub \(tag)", what: "it was \(state)")) }
                if old[1] != ci, ["passing", "failing"].contains(ci) { events.append(Event(when: stamp, source: "GitHub \(tag)", what: "CI is now \(ci)", ciFailed: ci == "failing" ? true : nil, quiet: ci == "passing" ? true : nil)) }
                if old[2] != mergeable, mergeable == "conflicting" { events.append(Event(when: stamp, source: "GitHub \(tag)", what: "it has conflicts with its base")) }
            }
        }
        return (events, current)
    }

    /// Answers and replies in a GitHub discussion since `since`.
    static func discussion(repo: String, number: Int, since: String) async -> [Event]? {
        let parts = repo.split(separator: "/")
        guard parts.count == 2, let gh = GitHub.binary else { return nil }
        let query = """
        query($o: String!, $n: String!, $d: Int!) { repository(owner: $o, name: $n) { discussion(number: $d) {
          comments(last: 30) { nodes { author { login } createdAt body replies(last: 30) { nodes { author { login } createdAt body } } } }
        } } }
        """
        guard let r = try? await Shell.run(gh, ["api", "graphql", "-f", "query=\(query)", "-f", "o=\(parts[0])", "-f", "n=\(parts[1])", "-F", "d=\(number)"]),
              r.status == 0 else { return nil }
        struct Author: Decodable { let login: String }
        struct Reply: Decodable { let author: Author?; let createdAt: String; let body: String? }
        struct Replies: Decodable { let nodes: [Reply] }
        struct Comment: Decodable { let author: Author?; let createdAt: String; let body: String?; let replies: Replies? }
        struct Comments: Decodable { let nodes: [Comment] }
        struct D: Decodable { let comments: Comments }
        struct Repo: Decodable { let discussion: D? }
        struct DataPart: Decodable { let repository: Repo? }
        struct Env: Decodable { let data: DataPart? }
        guard let d = (try? JSONDecoder().decode(Env.self, from: r.out))?.data?.repository?.discussion else { return nil }
        let me = await myLogin()
        var all: [Reply] = []
        for c in d.comments.nodes {
            all.append(Reply(author: c.author, createdAt: c.createdAt, body: c.body))
            all += c.replies?.nodes ?? []
        }
        return all.compactMap { c in
            guard after(c.createdAt, since), let who = c.author?.login, who != me, !isBot(who) else { return nil }
            return Event(when: c.createdAt, source: "Discussion \(parts[1])#\(number)", what: "\(who) answered" + snippet(c.body))
        }
    }

    static func snippet(_ body: String?) -> String {
        let flat = (body ?? "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard !flat.isEmpty else { return "" }
        return ": \"" + (flat.count > 140 ? String(flat.prefix(140)) + "…" : flat) + "\""
    }

    // MARK: The agent

    /// The one line typed into the card's agent. One line, because a new line would send it half written.
    static func wakeMessage(_ id: String, _ events: [Event]) -> String {
        "Quicksave: there is news on \(id) while it waits in Pending for inputs. "
            + events.map(\.line).joined(separator: " · ")
            + " · Read it and carry on with the task. If someone needs an answer, write me the draft: never post it yourself."
    }

    /// The line typed into the agent of a card in review whose CI went red: fix it, and say how in one line.
    static func fixMessage(_ id: String, _ events: [Event]) -> String {
        "Quicksave: \(id) is in review and its CI is red. "
            + events.map(\.line).joined(separator: " · ")
            + " · Find why it fails and fix it. Alejandro authorises you to commit and push the CI fix to this pull request's branch, and nothing else: no force push, no other branch, no merge, no comments. If the failure is not caused by this pull request (flaky test, main broken) or you cannot fix it, push nothing and say why. If there is review feedback above, do not act on it yet: list it for him. End your turn with one line in Spanish saying how you fixed it, or why not."
    }
}

/// Tells Alejandro something through Telegram, the one channel that reaches him (the vault's notify script).
enum Notify {
    static let script = NSHomeDirectory() + "/vault/Claude/hooks/notify.sh"

    @discardableResult
    static func send(_ text: String) async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: script) else { return false }
        // Telegram's Markdown breaks on a stray underscore or asterisk from an agent's reply.
        let safe = text.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "'").replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
        return (try? await Shell.run(script, [safe]))?.status == 0
    }
}

extension AgentJob {
    /// Reads Slack threads and returns the messages written after a moment by anyone but Alejandro. Only reads.
    static func slackNews(threads: [String], since: String) -> AgentJob {
        AgentJob(
            name: "slack watch",
            directory: NSTemporaryDirectory(),
            prompt: """
            Read these Slack threads and return every message posted after \(since) (UTC) by someone other than Alejandro Temina. Bots count only when they say something a person would act on.

            \(threads.map { "- " + $0 }.joined(separator: "\n"))

            How:
            - The Slack tools are deferred: load them first with ToolSearch (select:mcp__claude_ai_Slack__slack_read_thread), then read each thread with slack_read_thread. The channel id is after /archives/ and the thread ts is the number after p, with a dot before its last six digits.
            - Read only. Never send, draft or schedule anything.

            Return the structured result: messages, each with link (the thread it is in), author, when (ISO 8601 in UTC) and text (one line, at most 140 characters). An empty list when nothing is new.
            """,
            model: "claude-haiku-5-5",
            allowed: ["ToolSearch", "mcp__claude_ai_Slack__slack_read_thread", "mcp__claude_ai_Slack__slack_read_channel"],
            denied: ["mcp__claude_ai_Slack__slack_send_message", "mcp__claude_ai_Slack__slack_send_message_draft",
                     "mcp__claude_ai_Slack__slack_schedule_message", "Bash", "Write", "Edit"],
            schema: """
            {"type":"object","properties":{"messages":{"type":"array","items":{"type":"object","properties":{"link":{"type":"string"},"author":{"type":"string"},"when":{"type":"string"},"text":{"type":"string"}},"required":["author","when","text"]}}},"required":["messages"]}
            """,
            maxTurns: 12)
    }
}

struct SlackNewsResult: Decodable {
    struct Message: Decodable { let link: String?; let author: String; let when: String; let text: String }
    let messages: [Message]
}
