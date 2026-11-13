import AppKit
import Foundation

/// Pull requests waiting for his review, the review an agent prepares for each, and publishing it. See docs/reviews.md.

/// A pull request of alan-apps where his review is requested by name.
struct ReviewRequest: Identifiable, Hashable {
    let number: Int
    let title: String
    let url: URL
    let author: String
    let created: Date?
    let additions: Int
    let deletions: Int
    let changedFiles: Int
    /// People and teams asked to review, him included.
    let reviewers: Int
    let headRef: String
    let baseRef: String
    let isDraft: Bool
    var id: Int { number }
    /// Many reviewers (the usual six): his review matters less, so it goes in its own group.
    var shared: Bool { reviewers > Reviews.manyReviewers }
}

enum ReviewVerdict: String, Codable, CaseIterable {
    case approve = "APPROVE", comment = "COMMENT", requestChanges = "REQUEST_CHANGES"
    var title: String {
        switch self {
        case .approve: return "Approve"
        case .comment: return "Comment"
        case .requestChanges: return "Request changes"
        }
    }
}

struct ReviewComment: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var path: String
    var line: Int
    var emoji: String
    var text: String
    var dropped = false
    /// When it was posted on GitHub. A published comment is locked.
    var published: Date? = nil
    /// Changed by his notes and not looked at since.
    var touched = false
    /// Its id on GitHub once published, to follow its thread.
    var githubId: Int? = nil
    /// The answers under it on GitHub, oldest first.
    var thread: [ThreadPost]? = nil
    /// His answer to the thread, not yet posted.
    var reply: String? = nil
    /// After new commits: whether the author dealt with it, and how, in one line.
    var addressed: Bool? = nil
    var status: String? = nil

    var pendingReply: String? {
        guard published != nil, let r = reply?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else { return nil }
        return r
    }
}

/// A message on GitHub: an answer in a comment's thread, or a comment on the pull request's conversation.
struct ThreadPost: Codable, Hashable, Identifiable {
    let id: Int
    let author: String
    let body: String
    let created: Date?
    let mine: Bool
}

/// The review of one pull request, as it lives in Quicksave until he publishes it.
struct PRReview: Codable {
    enum State: String, Codable { case preparing, ready, failed }
    var number: Int
    var title: String
    var url: String
    var author: String
    var headRef: String
    var baseRef: String
    var state: State = .preparing
    var error: String? = nil
    var worktree: String? = nil
    var context = ""
    var verdict: ReviewVerdict = .comment
    var body = ""
    var bodyPublished: Date? = nil
    var verdictPublished: ReviewVerdict? = nil
    var comments: [ReviewComment] = []
    var flowPage: String? = nil
    var notes = ""
    /// What his last notes changed, in one sentence.
    var lastChange: String? = nil
    var session: String? = nil
    var cost: Double? = nil
    var started = Date()
    /// Comments on the pull request's conversation by other people, since he started the review.
    var conversation: [ThreadPost]? = nil
    /// The branch when he last published, and now: new commits mean the author answered with code.
    var headAtPublish: String? = nil
    var commitsAtPublish: Int? = nil
    var headNow: String? = nil
    var commitsNow: Int? = nil
    /// The head the last re-review looked at, and what it found.
    var recheckedHead: String? = nil
    var recheck: String? = nil
    /// Activity he has already seen, by id (r<reply>, c<comment>, h<head>).
    var seenActivity: [String]? = nil

    var newCommits: Int {
        guard let now = headNow, let then = headAtPublish, now != then else { return 0 }
        return max(1, (commitsNow ?? 0) - (commitsAtPublish ?? 0))
    }
    /// Everything that happened on GitHub since he published, by id.
    var activity: [String] {
        let replies = comments.flatMap { $0.thread ?? [] }.filter { !$0.mine }.map { "r\($0.id)" }
        let talk = (conversation ?? []).map { "c\($0.id)" }
        return replies + talk + (newCommits > 0 ? ["h\(headNow ?? "")"] : [])
    }
    var unseenActivity: [String] { let seen = Set(seenActivity ?? []); return activity.filter { !seen.contains($0) } }
    var newReplies: Int { unseenActivity.filter { $0.hasPrefix("r") || $0.hasPrefix("c") }.count }
    var pendingReplies: [ReviewComment] { comments.filter { $0.pendingReply != nil } }
    var hasPending: Bool { pendingEvent != nil || !pendingReplies.isEmpty }

    var everPublished: Bool { verdictPublished != nil }
    var unpublished: [ReviewComment] { comments.filter { !$0.dropped && $0.published == nil } }
    /// What the publish button would post now.
    var pendingEvent: ReviewVerdict? {
        if verdictPublished == nil { return verdict }
        if verdict != verdictPublished { return verdict }
        let bodyPending = bodyPublished == nil && !Reviews.withoutLegend(body).isEmpty
        return unpublished.isEmpty && !bodyPending ? nil : .comment
    }
}

enum Reviews {
    static let repo = "alan-eu/alan-apps"
    static let manyReviewers = 3
    static let parentName = "⛔ PR reviews"
    static let vsCodeProfile = "Review"
    static let legend = "[Legend](https://gist.github.com/nicoolas25/bbc2baf760e273e069361d0e1383587f) of the emoji in comments."

    /// The emoji legend, lightest weight last.
    static let emojis: [(emoji: String, name: String)] = [
        ("🔧", "Needs to change"), ("⚠️", "Possible error"), ("❓", "Question"), ("🤔", "Thinking out loud"),
        ("♻️", "Optional refactor"), ("🌱", "Seed for the future"), ("📌", "Out of scope, follow-up"),
        ("📝", "Note"), ("🏕", "Leave it cleaner"), ("💡", "Learned something"), ("🍖", "Food for thought"), ("👍", "I like this"),
    ]

    /// Where the agent writes the flow page and Quicksave the payload it publishes. No space-free path is needed:
    /// the permission is matched on the absolute path.
    static let folder: String = {
        let path = NSHomeDirectory() + "/Library/Application Support/Quicksave/reviews"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }()

    static func folder(_ number: Int) -> String {
        let path = folder + "/\(number)"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    /// The text without the legend line, if an agent or an older review left it in.
    static func withoutLegend(_ text: String) -> String {
        text.components(separatedBy: "\n").filter { !$0.contains("nicoolas25/bbc2baf760e273e069361d0e1383587f") }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: GitHub

    static func requested() async throws -> [ReviewRequest] {
        guard let gh = GitHub.binary else { throw QuicksaveError.message("The gh command is not installed.") }
        let fields = "number,title,url,author,createdAt,additions,deletions,changedFiles,reviewRequests,headRefName,baseRefName,isDraft"
        let r = try await Shell.run(gh, ["pr", "list", "--repo", repo, "--state", "open", "--search", "user-review-requested:@me",
                                         "--json", fields, "--limit", "100"])
        guard r.status == 0 else {
            throw QuicksaveError.message(String(data: r.err, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "gh failed")
        }
        struct Raw: Decodable {
            struct Author: Decodable { let login: String }
            let number: Int, title: String, url: String, createdAt: String, additions: Int, deletions: Int, changedFiles: Int
            let author: Author?, reviewRequests: [[String: String?]]?, headRefName: String, baseRefName: String, isDraft: Bool
        }
        let raws = try JSONDecoder().decode([Raw].self, from: r.out)
        return raws.compactMap { p in
            guard let url = URL(string: p.url) else { return nil }
            return ReviewRequest(number: p.number, title: p.title, url: url, author: p.author?.login ?? "", created: QSDate.parse(p.createdAt),
                                 additions: p.additions, deletions: p.deletions, changedFiles: p.changedFiles,
                                 reviewers: p.reviewRequests?.count ?? 1, headRef: p.headRefName, baseRef: p.baseRefName, isDraft: p.isDraft)
        }.sorted { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }
    }

    /// OPEN, MERGED or CLOSED, or nil when GitHub could not be read.
    static func state(of number: Int) async -> String? {
        guard let gh = GitHub.binary, let r = try? await Shell.run(gh, ["pr", "view", "\(number)", "--repo", repo, "--json", "state"]),
              r.status == 0, let obj = try? JSONSerialization.jsonObject(with: r.out) as? [String: Any] else { return nil }
        return obj["state"] as? String
    }

    /// Runs `gh` and returns what it printed, or throws what it said.
    static func gh(_ args: [String]) async throws -> Data {
        guard let gh = GitHub.binary else { throw QuicksaveError.message("The gh command is not installed.") }
        let r = try await Shell.run(gh, args)
        guard r.status == 0 else {
            let said = String(data: r.err, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw QuicksaveError.message(said.isEmpty ? "gh failed" : said)
        }
        return r.out
    }

    /// His GitHub login, read once.
    nonisolated(unsafe) private static var cachedLogin: String?
    static func login() async -> String? {
        if let cachedLogin { return cachedLogin }
        guard let data = try? await gh(["api", "user", "--jq", ".login"]) else { return nil }
        cachedLogin = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return cachedLogin
    }

    /// The branch's head commit and how many commits the pull request has.
    static func head(of number: Int) async -> (sha: String, commits: Int)? {
        guard let data = try? await gh(["pr", "view", "\(number)", "--repo", repo, "--json", "headRefOid,commits"]),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let sha = obj["headRefOid"] as? String
        else { return nil }
        return (sha, (obj["commits"] as? [Any])?.count ?? 0)
    }

    struct RawComment: Decodable {
        struct User: Decodable { let login: String; let type: String? }
        let id: Int
        let in_reply_to_id: Int?
        let user: User?
        let body: String
        let created_at: String
        let path: String?
        let line: Int?
        let original_line: Int?
        let pull_request_review_id: Int?
        var bot: Bool { user?.type == "Bot" || (user?.login.hasSuffix("[bot]") ?? false) }
    }

    /// Review comments of a pull request, and the comments of its conversation.
    static func discussion(_ number: Int) async throws -> (review: [RawComment], talk: [RawComment]) {
        let review = try JSONDecoder().decode([RawComment].self,
                                              from: try await gh(["api", "repos/\(repo)/pulls/\(number)/comments?per_page=100"]))
        let talk = try JSONDecoder().decode([RawComment].self,
                                            from: try await gh(["api", "repos/\(repo)/issues/\(number)/comments?per_page=100"]))
        return (review, talk)
    }

    struct Published {
        let event: ReviewVerdict
        let body: Bool
        /// Our comment id to its GitHub id.
        let comments: [String: Int]
        let replies: [String: ThreadPost]
        let head: (sha: String, commits: Int)?
        let failedReplies: [String]
    }

    /// Posts what is kept and not yet published as one review, then his replies to threads. Returns what it posted.
    static func publish(_ review: PRReview) async throws -> Published {
        var event: ReviewVerdict = .comment
        var sendBody = false
        var ids: [String: Int] = [:]
        if let pending = review.pendingEvent {
            event = pending
            let body = withoutLegend(review.body)
            // The first review always carries the main comment, with the legend under it. Later ones carry only what is new.
            sendBody = review.bodyPublished == nil && (!body.isEmpty || !review.everPublished)
            if event == .requestChanges && !sendBody && review.bodyPublished == nil {
                throw QuicksaveError.message("Requesting changes needs a main comment.")
            }
            let comments = review.unpublished
            var payload: [String: Any] = ["event": event.rawValue,
                                          "comments": comments.map { ["path": $0.path, "line": $0.line, "side": "RIGHT",
                                                                      "body": "\($0.emoji) \($0.text)"] }]
            if sendBody { payload["body"] = body.isEmpty ? legend : body + "\n\n" + legend }
            let file = folder(review.number) + "/publish.json"
            try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: file))
            let out: Data
            do { out = try await gh(["api", "--method", "POST", "repos/\(repo)/pulls/\(review.number)/reviews", "--input", file]) }
            catch { throw QuicksaveError.message("GitHub did not take the review: \(error.localizedDescription)") }
            // Each comment's GitHub id, to follow its thread.
            if let reviewId = (try? JSONSerialization.jsonObject(with: out) as? [String: Any])?["id"] as? Int,
               let data = try? await gh(["api", "repos/\(repo)/pulls/\(review.number)/reviews/\(reviewId)/comments?per_page=100"]),
               let posted = try? JSONDecoder().decode([RawComment].self, from: data) {
                for c in comments {
                    if let g = posted.first(where: { $0.path == c.path && $0.body.hasPrefix(c.emoji) && $0.body.contains(c.text.prefix(40)) }) {
                        ids[c.id] = g.id
                    }
                }
            }
        }
        var replies: [String: ThreadPost] = [:]
        var failed: [String] = []
        for c in review.pendingReplies {
            guard let gid = c.githubId, let text = c.pendingReply else { failed.append("\(c.path):\(c.line)"); continue }
            do {
                let out = try await gh(["api", "--method", "POST", "repos/\(repo)/pulls/\(review.number)/comments/\(gid)/replies", "-f", "body=\(text)"])
                let id = (try? JSONSerialization.jsonObject(with: out) as? [String: Any])?["id"] as? Int ?? 0
                replies[c.id] = ThreadPost(id: id, author: await login() ?? "you", body: text, created: Date(), mine: true)
            } catch { failed.append("\(c.path):\(c.line)") }
        }
        return Published(event: event, body: sendBody, comments: ids, replies: replies, head: await head(of: review.number),
                         failedReplies: failed)
    }

    // MARK: Worktrees

    private static let git = "/usr/bin/git"

    /// The review worktree of a pull request: a child of the "⛔ PR reviews" worktree, with the branch checked out and
    /// tracking its remote, so the editor shows the pull request. Reused when it already exists.
    static func worktree(for pr: ReviewRequest) async throws -> String {
        let name = "Review PR \(pr.number)"
        if let w = await Orca.worktree(named: name), FileManager.default.fileExists(atPath: w.path) { return w.path }
        let parent = try await parentWorktree()
        let created = try await Orca.run(["worktree", "create", "--repo", "name:alan-apps", "--name", name,
                                          "--parent-worktree", "path:\(parent)", "--pr", "\(pr.number)",
                                          "--comment", "Review of #\(pr.number) \(pr.title), by Quicksave", "--setup", "skip", "--json"])
        guard let path = findPath(in: created) else { throw QuicksaveError.message("Orca did not say where the review worktree is.") }
        let b = pr.headRef
        try await gitStep(path, ["config", "--add", "remote.origin.fetch", "+refs/heads/\(b):refs/remotes/origin/\(b)"])
        try await gitStep(path, ["fetch", "origin", b, pr.baseRef])
        try await gitStep(path, ["checkout", "-B", b, "--track", "origin/\(b)"])
        try await gitStep(path, ["config", "branch.\(b).github-pr-owner-number", "alan-eu#alan-apps#\(pr.number)"])
        return path
    }

    /// The parent every review worktree hangs from, created the first time. Its emoji says it is never deleted.
    private static func parentWorktree() async throws -> String {
        if let w = await Orca.worktree(named: parentName), FileManager.default.fileExists(atPath: w.path) { return w.path }
        let created = try await Orca.run(["worktree", "create", "--repo", "name:alan-apps", "--name", parentName, "--no-parent",
                                          "--comment", "Parent of every PR review worktree Quicksave opens. Never delete it.",
                                          "--setup", "skip", "--json"])
        guard let path = findPath(in: created) else { throw QuicksaveError.message("Orca did not say where the reviews parent worktree is.") }
        return path
    }

    /// Brings the review worktree to the branch as it is now on GitHub. It is a review-only checkout: nothing local to keep.
    static func updateWorktree(_ path: String, branch b: String) async throws {
        try await gitStep(path, ["fetch", "origin", b])
        try await gitStep(path, ["checkout", "-B", b, "--track", "origin/\(b)"])
        try await gitStep(path, ["reset", "--hard", "origin/\(b)"])
    }

    static func removeWorktree(_ path: String) async {
        _ = try? await Orca.run(["worktree", "rm", "--worktree", "path:\(path)", "--json"])
    }

    private static func gitStep(_ dir: String, _ args: [String]) async throws {
        let r = try await Shell.run(git, ["-C", dir] + args)
        guard r.status == 0 else {
            let said = String(data: r.err, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw QuicksaveError.message("git \(args.first ?? "") failed in the review worktree: \(said)")
        }
    }

    /// The first "path" anywhere in Orca's answer.
    private static func findPath(in data: Data) -> String? {
        func walk(_ v: Any) -> String? {
            if let d = v as? [String: Any] {
                if let p = d["path"] as? String, p.hasPrefix("/") { return p }
                for (_, x) in d { if let p = walk(x) { return p } }
            } else if let a = v as? [Any] {
                for x in a { if let p = walk(x) { return p } }
            }
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)).flatMap(walk)
    }

    // MARK: VS Code

    static var codeBinary: String? {
        ["/usr/local/bin/code", "/opt/homebrew/bin/code",
         "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Opens the worktree in VS Code with the review profile, at a file and line when given.
    static func openInCode(_ worktree: String, file: String? = nil, line: Int? = nil) {
        guard let code = codeBinary else { return }
        var args = ["--profile", vsCodeProfile, worktree]
        if let file {
            let full = file.hasPrefix("/") ? file : worktree + "/" + file
            args += ["-g", line.map { "\(full):\($0)" } ?? full]
        }
        Task.detached { _ = try? await Shell.run(code, args) }
    }
}

// MARK: Agents

extension AgentJob {
    static let reviewReads = ["Read", "Grep", "Glob", "ToolSearch", "Agent", "Task",
                              "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)", "Bash(git rev-parse:*)",
                              "Bash(git merge-base:*)", "Bash(git grep:*)", "Bash(git ls-files:*)", "Bash(git fetch:*)",
                              "Bash(gh pr view:*)", "Bash(gh pr diff:*)", "Bash(gh pr list:*)", "Bash(date:*)",
                              "mcp__claude_ai_Slack__slack_search_public_and_private", "mcp__claude_ai_Slack__slack_search_public",
                              "mcp__claude_ai_Slack__slack_read_thread", "mcp__claude_ai_Slack__slack_read_channel",
                              "mcp__claude_ai_Slack__slack_search_channels", "mcp__claude_ai_Slack__slack_search_users",
                              "mcp__claude_ai_Notion__notion-search", "mcp__claude_ai_Notion__notion-fetch"] + Morning.readLinear
    /// No "Edit" here: denying Edit also denies every file write, which killed the flow page (12-nov). Unlisted edits are
    /// refused anyway, since the job runs in dontAsk mode.
    static let reviewNever = Morning.neverPost + ["NotebookEdit", "Bash(git push:*)", "Bash(git commit:*)", "Bash(git checkout:*)",
                                                  "Bash(git reset:*)", "Bash(gh api:*)", "Bash(gh pr review:*)", "Bash(gh pr comment:*)",
                                                  "Bash(gh pr merge:*)", "Bash(gh pr close:*)", "Bash(gh pr edit:*)",
                                                  "mcp__claude_ai_Slack__slack_send_message_draft", "mcp__claude_ai_Linear__save_issue"]

    /// Prepares his review: context, pre-pass, verdict, main comment and the flow page. Posts nothing.
    static func reviewPrepare(_ pr: ReviewRequest, worktree: String) -> AgentJob {
        let out = Reviews.folder(pr.number)
        let vault = NSHomeDirectory() + "/vault"
        return AgentJob(
            name: "review #\(pr.number)",
            directory: worktree,
            prompt: """
            You prepare Alejandro's review of pull request #\(pr.number) "\(pr.title)" by \(pr.author) in \(Reviews.repo) (\(pr.url.absoluteString)). Quicksave started you when he pressed Start review. He reads your result in the app, changes what he wants, and publishes it himself. You never post anything anywhere.

            The current folder is a worktree with the branch \(pr.headRef) checked out. The base is origin/\(pr.baseRef): always diff against it (`git diff origin/\(pr.baseRef)...HEAD`), never against a local main.

            Do this:
            1. Read \(vault)/Claude/skills/pr-review-copilot/SKILL.md. Follow its Step 4 (the true diff), Step 5 (the context pack: vault first, the pull request and its stack, Linear, Notion, Slack) and Step 5b (the pre-pass). Skip its Steps 1 to 3 (done), 6 to 8 (he does them in the app) and any question to him: nobody is there to answer.
            2. The pre-pass looks first at the product and the decisions, then at the code: is the problem the right one, do the decisions hold and match what was agreed in Linear, Slack or Notion, what changes for members or users, and the risky areas (health data, permissions, money, migrations, anything in shared/). Code style only when it matters. At most 8 comments, fewer is better. Each comment sits on a line ADDED by the diff (the RIGHT side): check it with `git diff origin/\(pr.baseRef)...HEAD -- <file>`, or GitHub rejects the whole review. Pick the emoji from the skill's legend, conservatively. Praise (👍) is welcome when deserved.
            3. Read \(vault)/Claude/skills/code-flow/SKILL.md and its example.html, and build the flow page of this pull request following them, with two differences: write it as one HTML file to "\(out)/flow.html" with the Write tool instead of publishing an Artifact, and keep each VS Code link as a real `vscode://file/<absolute path in this worktree>:<line>` link (Quicksave opens it), not a copy button. Skip the page when the pull request has no flow (renames, copy, config, dependency bumps) and set flowPage to false.
            4. Propose a verdict and the main comment.

            \(Morning.howToRun)
            - Notion tools are deferred too.

            Return the structured result, written in English, no em-dashes, every issue or PR code with a 2-3 word tag:
            - context: the short pack in Markdown, at most 15 lines: **Problem** (two lines), **Decisions** (two or three bullets, marking those with no recorded reason), **Look hard** (the risky files, one bullet each with what to check). End with one line saying what is safe to skim.
            - verdict: APPROVE, COMMENT or REQUEST_CHANGES, your recommendation.
            - body: the main comment of the review, in his voice: short, direct, friendly. No link to the emoji legend: Quicksave adds it when he publishes.
            - comments: path (relative to the repository), line, emoji, and text without the emoji.
            - flowPage: true when you wrote the page.
            - linear: the Linear issue of the pull request with its tag, or empty.
            """,
            model: "claude-opus-5-5",
            allowed: reviewReads + ["Write(/\(out)/**)", "Edit(/\(out)/**)"],
            denied: reviewNever,
            schema: """
            {"type":"object","properties":{"context":{"type":"string"},"verdict":{"type":"string","enum":["APPROVE","COMMENT","REQUEST_CHANGES"]},"body":{"type":"string"},"comments":{"type":"array","items":{"type":"object","properties":{"path":{"type":"string"},"line":{"type":"integer"},"emoji":{"type":"string"},"text":{"type":"string"}},"required":["path","line","emoji","text"]}},"flowPage":{"type":"boolean"},"linear":{"type":"string"}},"required":["context","verdict","body","comments","flowPage"]}
            """,
            maxTurns: 160,
            extraDirectories: [vault, out])
    }

    /// Folds what he dictated into the review: new comments, changed texts and emojis, the main comment, the verdict.
    /// It continues the session that prepared the review, so it remembers the code and the context.
    static func reviewNotes(_ review: PRReview, notes: String) -> AgentJob {
        struct Item: Encodable { let id: String; let path: String; let line: Int; let emoji: String; let text: String; let dropped: Bool }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        func json(_ c: [ReviewComment]) -> String {
            let items = c.map { Item(id: $0.id, path: $0.path, line: $0.line, emoji: $0.emoji, text: $0.text, dropped: $0.dropped) }
            return (try? enc.encode(items)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        }
        let open = review.comments.filter { $0.published == nil }
        let done = review.comments.filter { $0.published != nil }
        return AgentJob(
            name: "review notes #\(review.number)",
            directory: review.worktree ?? NSTemporaryDirectory(),
            prompt: """
            Alejandro is reviewing pull request #\(review.number) "\(review.title)" in Quicksave, with the review you prepared in this session. He read the code and dictated his thoughts (by voice, so expect loose wording). Fold them into the review.

            His notes:
            <<<
            \(notes)
            >>>

            The review as it is now (he may have edited it by hand: his edits win unless his notes say otherwise):
            - verdict: \(review.verdict.rawValue)\(review.verdictPublished.map { " (already published as \($0.rawValue))" } ?? "")
            - main comment\(review.bodyPublished != nil ? " (already published, do not change it)" : ""):
            <<<
            \(review.body)
            >>>
            - comments not yet published:
            \(json(open))
            \(done.isEmpty ? "" : "- comments already published, read-only, never return them in `comments`. Their threads on GitHub, with any answer he drafted:\n" + AgentJob.threads(done))

            Rules:
            - Return every not-yet-published comment, with its id, changed or not. To drop one, set dropped true. A new comment has no id.
            - A new comment must sit on a line ADDED by the diff: check with `git diff origin/\(review.baseRef)...HEAD -- <file>`. If what he says is about the whole pull request, it goes in the main comment.
            - Never add a link to the emoji legend: Quicksave adds it when he publishes.
            - If his notes answer someone in the thread of a published comment, return it in `replies`: the id of that published comment and the full text of his answer (it replaces any draft he had there).
            - Turn his words into clean review comments in his voice: English, short, direct, no em-dashes. Keep his meaning, do not add opinions he did not give. The emoji follows the weight he gives it.
            - Change the verdict only if his notes say so or plainly imply it.
            - summary: one sentence on what you changed.

            \(Morning.howToRun)
            """,
            model: "claude-sonnet-5-5",
            allowed: reviewReads,
            denied: reviewNever + ["Edit", "Write"],
            schema: """
            {"type":"object","properties":{"verdict":{"type":"string","enum":["APPROVE","COMMENT","REQUEST_CHANGES"]},"body":{"type":"string"},"comments":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"path":{"type":"string"},"line":{"type":"integer"},"emoji":{"type":"string"},"text":{"type":"string"},"dropped":{"type":"boolean"}},"required":["path","line","emoji","text"]}},"replies":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"text":{"type":"string"}},"required":["id","text"]}},"summary":{"type":"string"}},"required":["verdict","body","comments","summary"]}
            """,
            maxTurns: 40,
            resume: review.session)
    }
}

extension AgentJob {
    /// Published comments with their GitHub threads, for an agent to read.
    static func threads(_ comments: [ReviewComment]) -> String {
        comments.map { c in
            var lines = ["[id \(c.id)] \(c.path):\(c.line) \(c.emoji) \(c.text)"]
            for p in c.thread ?? [] { lines.append("    \(p.mine ? "Alejandro" : p.author): \(p.body)") }
            if let r = c.pendingReply { lines.append("    (his draft answer, not posted) \(r)") }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    /// After the author pushed new commits: checks each of his published comments against them, drafts answers to the
    /// threads, and proposes new comments only for what is new. It continues the session that prepared the review.
    static func reviewRecheck(_ review: PRReview) -> AgentJob {
        let published = review.comments.filter { $0.published != nil }
        return AgentJob(
            name: "review recheck #\(review.number)",
            directory: review.worktree ?? NSTemporaryDirectory(),
            prompt: """
            The author of pull request #\(review.number) "\(review.title)" pushed new commits after Alejandro published his review. The worktree now holds the branch as it is on GitHub. Check them for him. He decides everything in Quicksave; you never post anything.

            What changed since his review: `git diff \(review.headAtPublish ?? "origin/\(review.baseRef)")..HEAD` (and `git log` over the same range).
            The whole pull request, for line numbers: `git diff origin/\(review.baseRef)...HEAD`.

            His published comments and their threads on GitHub:
            \(AgentJob.threads(published))

            \((review.conversation ?? []).isEmpty ? "" : "The pull request's conversation since:\n" + (review.conversation ?? []).map { "    \($0.author): \($0.body)" }.joined(separator: "\n"))

            Return:
            - statuses: one per published comment above, by its id: addressed (true when the new code or the author's answer deals with it) and status, one short line saying how or what is still missing.
            - replies: for a thread where the author answered and a short answer from him makes sense (thanks, a follow-up question, agreeing), the comment's id and the text, in his voice. Leave out threads that need nothing.
            - comments: new comments only for problems the new commits introduce, on lines ADDED by the whole pull request's diff (check with git diff), at most 4, often none. Path, line, emoji from the legend, text without the emoji.
            - verdict: APPROVE, COMMENT or REQUEST_CHANGES, what you now recommend.
            - summary: one or two sentences for him: what the new commits did with his review.

            English, short, direct, no em-dashes, every issue or PR code with a 2-3 word tag. No link to the emoji legend.

            \(Morning.howToRun)
            """,
            model: "claude-opus-5-5",
            allowed: reviewReads,
            denied: reviewNever + ["Edit", "Write"],
            schema: """
            {"type":"object","properties":{"statuses":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"addressed":{"type":"boolean"},"status":{"type":"string"}},"required":["id","addressed","status"]}},"replies":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"text":{"type":"string"}},"required":["id","text"]}},"comments":{"type":"array","items":{"type":"object","properties":{"path":{"type":"string"},"line":{"type":"integer"},"emoji":{"type":"string"},"text":{"type":"string"}},"required":["path","line","emoji","text"]}},"verdict":{"type":"string","enum":["APPROVE","COMMENT","REQUEST_CHANGES"]},"summary":{"type":"string"}},"required":["statuses","comments","verdict","summary"]}
            """,
            maxTurns: 80,
            resume: review.session)
    }
}

struct ReviewPrepareResult: Decodable {
    struct Comment: Decodable { let path: String; let line: Int; let emoji: String; let text: String }
    let context: String
    let verdict: String
    let body: String
    let comments: [Comment]
    let flowPage: Bool
    let linear: String?
}

struct ReviewNotesResult: Decodable {
    struct Reply: Decodable { let id: String; let text: String }
    struct Comment: Decodable { let id: String?; let path: String; let line: Int; let emoji: String; let text: String; let dropped: Bool? }
    let verdict: String
    let body: String
    let comments: [Comment]
    let replies: [Reply]?
    let summary: String
}

struct ReviewRecheckResult: Decodable {
    struct Status: Decodable { let id: String; let addressed: Bool; let status: String }
    let statuses: [Status]
    let comments: [ReviewNotesResult.Comment]
    let replies: [ReviewNotesResult.Reply]?
    let verdict: String
    let summary: String
}

// MARK: Store

extension Store {
    nonisolated(unsafe) static var devReviewDone = false

    static func savedReviews() -> [Int: PRReview] {
        let saved = Database.shared.value("reviews", as: [String: PRReview].self) ?? [:]
        var out: [Int: PRReview] = [:]
        for (k, var v) in saved {
            guard let n = Int(k) else { continue }
            // Reviews prepared before 12-nov carry the legend in the text; it is added on publish now.
            if v.bodyPublished == nil { v.body = Reviews.withoutLegend(v.body) }
            out[n] = v
        }
        return out
    }

    private func saveReviews() {
        Database.shared.setValue("reviews", Dictionary(uniqueKeysWithValues: reviews.map { ("\($0.key)", $0.value) }))
    }

    /// Changes one review and keeps it.
    func editReview(_ number: Int, _ change: (inout PRReview) -> Void) {
        guard var r = reviews[number] else { return }
        change(&r)
        reviews[number] = r
        saveReviews()
    }

    /// Pull requests whose review he started but that are no longer requested (he published, or was removed), still open.
    var reviewedOnly: [PRReview] {
        let requested = Set(reviewRequests.map(\.number))
        return reviews.values.filter { !requested.contains($0.number) }.sorted { $0.started < $1.started }
    }

    func refreshReviews() async {
        do {
            reviewRequests = try await Reviews.requested()
            reviewsError = nil
        } catch {
            reviewsError = error.localizedDescription
            return
        }
        // For development: QUICKSAVE_REVIEW=<number> opens that pull request and starts its review once.
        if !Self.devReviewDone, let n = ProcessInfo.processInfo.environment["QUICKSAVE_REVIEW"].flatMap(Int.init),
           let pr = reviewRequests.first(where: { $0.number == n }) {
            Self.devReviewDone = true
            tab = .reviews
            reviewOpen = n
            if reviews[n]?.state != .ready { Task { await startReview(pr) } }
        }
        // A preparation that has no agent behind it any more (the app was closed while it ran) has failed.
        for (n, r) in reviews where r.state == .preparing && !reviewBusy.contains(n) {
            editReview(n) { $0.state = .failed; $0.error = "Quicksave closed while the review was being prepared." }
        }
        // Merged or closed: the review is over, its worktree goes.
        let requested = Set(reviewRequests.map(\.number))
        for (n, r) in reviews where !requested.contains(n) && !reviewBusy.contains(n) {
            guard let state = await Reviews.state(of: n), state != "OPEN" else { continue }
            if let w = r.worktree { await Reviews.removeWorktree(w) }
            reviews[n] = nil
            saveReviews()
            if reviewOpen == n { reviewOpen = nil }
        }
        // Published reviews: answers, conversation and new commits.
        for (n, r) in reviews where r.everPublished && !reviewBusy.contains(n) { await followReview(n) }
    }

    func startReview(_ pr: ReviewRequest) async {
        guard !reviewBusy.contains(pr.number) else { return }
        reviewBusy.insert(pr.number)
        defer { reviewBusy.remove(pr.number); reviewSteps[pr.number] = nil }
        reviews[pr.number] = PRReview(number: pr.number, title: pr.title, url: pr.url.absoluteString, author: pr.author,
                                      headRef: pr.headRef, baseRef: pr.baseRef, worktree: reviews[pr.number]?.worktree)
        saveReviews()
        do {
            reviewSteps[pr.number] = "Opening the worktree"
            let path = try await Reviews.worktree(for: pr)
            editReview(pr.number) { $0.worktree = path }
            reviewSteps[pr.number] = "Starting"
            let number = pr.number
            let run = try await Agents.run(.reviewPrepare(pr, worktree: path)) { step in
                Task { @MainActor [weak self] in self?.reviewSteps[number] = step }
            }
            guard let result = try? JSONDecoder().decode(ReviewPrepareResult.self, from: Data(run.resultJSON.utf8)) else {
                throw QuicksaveError.message("The agent's result could not be read: \(run.resultJSON.prefix(300))")
            }
            let flow = Reviews.folder(pr.number) + "/flow.html"
            editReview(pr.number) { r in
                r.state = .ready
                r.error = nil
                r.context = result.context
                r.verdict = ReviewVerdict(rawValue: result.verdict) ?? .comment
                r.body = Reviews.withoutLegend(result.body)
                r.comments = result.comments.map { ReviewComment(path: $0.path, line: $0.line, emoji: $0.emoji, text: $0.text) }
                r.flowPage = result.flowPage && FileManager.default.fileExists(atPath: flow) ? flow : nil
                r.session = run.sessionId
                r.cost = run.cost
            }
        } catch {
            editReview(pr.number) { $0.state = .failed; $0.error = error.localizedDescription }
        }
    }

    func applyNotes(_ number: Int) async {
        guard let review = reviews[number], !reviewBusy.contains(number) else { return }
        let notes = review.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { return }
        reviewBusy.insert(number)
        defer { reviewBusy.remove(number); reviewSteps[number] = nil }
        reviewNotice[number] = nil
        do {
            let run = try await Agents.run(.reviewNotes(review, notes: notes)) { step in
                Task { @MainActor [weak self] in self?.reviewSteps[number] = step }
            }
            guard let result = try? JSONDecoder().decode(ReviewNotesResult.self, from: Data(run.resultJSON.utf8)) else {
                throw QuicksaveError.message("The agent's result could not be read.")
            }
            editReview(number) { r in
                if let v = ReviewVerdict(rawValue: result.verdict) { r.verdict = v }
                if r.bodyPublished == nil { r.body = Reviews.withoutLegend(result.body) }
                for c in result.comments {
                    if let id = c.id, let i = r.comments.firstIndex(where: { $0.id == id }) {
                        guard r.comments[i].published == nil else { continue }
                        let old = r.comments[i]
                        r.comments[i].path = c.path; r.comments[i].line = c.line
                        r.comments[i].emoji = c.emoji; r.comments[i].text = c.text
                        r.comments[i].dropped = c.dropped ?? false
                        if r.comments[i] != old { r.comments[i].touched = true }
                    } else {
                        r.comments.append(ReviewComment(path: c.path, line: c.line, emoji: c.emoji, text: c.text,
                                                        dropped: c.dropped ?? false, touched: true))
                    }
                }
                for rp in result.replies ?? [] {
                    if let i = r.comments.firstIndex(where: { $0.id == rp.id }), r.comments[i].published != nil { r.comments[i].reply = rp.text }
                }
                r.lastChange = result.summary
                r.notes = ""
                if let s = run.sessionId { r.session = s }
            }
        } catch {
            reviewNotice[number] = error.localizedDescription
        }
    }

    func publishReview(_ number: Int) async {
        guard let review = reviews[number], !reviewBusy.contains(number) else { return }
        reviewBusy.insert(number)
        defer { reviewBusy.remove(number); reviewSteps[number] = nil }
        reviewSteps[number] = "Publishing"
        reviewNotice[number] = nil
        do {
            let reviewPending = review.pendingEvent != nil
            let sent = try await Reviews.publish(review)
            let now = Date()
            editReview(number) { r in
                if reviewPending {
                    if sent.event != .comment || r.verdictPublished == nil { r.verdictPublished = sent.event }
                    if sent.body { r.bodyPublished = now }
                    for i in r.comments.indices where r.comments[i].published == nil && !r.comments[i].dropped {
                        r.comments[i].published = now
                        r.comments[i].touched = false
                        r.comments[i].githubId = sent.comments[r.comments[i].id]
                    }
                    // New commits are counted from here.
                    if let h = sent.head { r.headAtPublish = h.sha; r.commitsAtPublish = h.commits; r.headNow = h.sha; r.commitsNow = h.commits }
                }
                for i in r.comments.indices {
                    guard let post = sent.replies[r.comments[i].id] else { continue }
                    r.comments[i].thread = (r.comments[i].thread ?? []) + [post]
                    r.comments[i].reply = nil
                }
            }
            if !sent.failedReplies.isEmpty {
                reviewNotice[number] = "Some replies could not be posted: \(sent.failedReplies.joined(separator: ", ")). They are still here."
            }
        } catch {
            reviewNotice[number] = error.localizedDescription
        }
    }

    /// Reads what happened on GitHub since he published: answers in his threads, the conversation, new commits.
    func followReview(_ number: Int) async {
        guard let review = reviews[number], review.everPublished, let me = await Reviews.login(),
              let d = try? await Reviews.discussion(number) else { return }
        let head = await Reviews.head(of: number)
        editReview(number) { r in
            for i in r.comments.indices where r.comments[i].published != nil {
                let c = r.comments[i]
                // Published before ids were kept: find it among his own comments.
                if c.githubId == nil, let g = d.review.first(where: { $0.in_reply_to_id == nil && $0.user?.login == me
                    && $0.path == c.path && $0.body.contains(c.text.prefix(40)) }) {
                    r.comments[i].githubId = g.id
                }
                guard let gid = r.comments[i].githubId else { continue }
                r.comments[i].thread = d.review.filter { $0.in_reply_to_id == gid && !$0.bot }
                    .map { ThreadPost(id: $0.id, author: $0.user?.login ?? "", body: $0.body, created: QSDate.parse($0.created_at),
                                      mine: $0.user?.login == me) }
            }
            r.conversation = d.talk.filter { !$0.bot && $0.user?.login != me && (QSDate.parse($0.created_at) ?? .distantPast) > r.started }
                .map { ThreadPost(id: $0.id, author: $0.user?.login ?? "", body: $0.body, created: QSDate.parse($0.created_at), mine: false) }
            if let head {
                r.headNow = head.sha; r.commitsNow = head.commits
                // Published before the head was kept: new commits count from the first look.
                if r.headAtPublish == nil { r.headAtPublish = head.sha; r.commitsAtPublish = head.commits }
            }
        }
    }

    func markActivitySeen(_ number: Int) {
        guard let r = reviews[number], !r.unseenActivity.isEmpty else { return }
        editReview(number) { $0.seenActivity = Array(Set(($0.seenActivity ?? []) + $0.activity)) }
    }

    /// Looks at the commits pushed since he published: did they deal with his comments, is there anything new to say.
    func recheckReview(_ number: Int) async {
        guard let review = reviews[number], let worktree = review.worktree, !reviewBusy.contains(number) else { return }
        reviewBusy.insert(number)
        defer { reviewBusy.remove(number); reviewSteps[number] = nil }
        reviewNotice[number] = nil
        do {
            reviewSteps[number] = "Updating the worktree"
            try await Reviews.updateWorktree(worktree, branch: review.headRef)
            let run = try await Agents.run(.reviewRecheck(review)) { step in
                Task { @MainActor [weak self] in self?.reviewSteps[number] = step }
            }
            guard let result = try? JSONDecoder().decode(ReviewRecheckResult.self, from: Data(run.resultJSON.utf8)) else {
                throw QuicksaveError.message("The agent's result could not be read.")
            }
            editReview(number) { r in
                for st in result.statuses {
                    guard let i = r.comments.firstIndex(where: { $0.id == st.id }) else { continue }
                    r.comments[i].addressed = st.addressed
                    r.comments[i].status = st.status
                }
                for rp in result.replies ?? [] {
                    guard let i = r.comments.firstIndex(where: { $0.id == rp.id }), r.comments[i].pendingReply == nil else { continue }
                    r.comments[i].reply = rp.text
                }
                for c in result.comments {
                    r.comments.append(ReviewComment(path: c.path, line: c.line, emoji: c.emoji, text: c.text, touched: true))
                }
                if let v = ReviewVerdict(rawValue: result.verdict) { r.verdict = v }
                r.recheck = result.summary
                r.recheckedHead = r.headNow
                if let s = run.sessionId { r.session = s }
            }
        } catch {
            reviewNotice[number] = error.localizedDescription
        }
    }
}
