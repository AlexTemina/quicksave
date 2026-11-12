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

    /// Posts what is kept and not yet published as one review. Returns what it posted.
    static func publish(_ review: PRReview) async throws -> (event: ReviewVerdict, body: Bool, comments: [String]) {
        guard let event = review.pendingEvent else { throw QuicksaveError.message("Nothing new to publish.") }
        let body = withoutLegend(review.body)
        // The first review always carries the main comment, with the legend under it. Later ones carry only what is new.
        let sendBody = review.bodyPublished == nil && (!body.isEmpty || !review.everPublished)
        if event == .requestChanges && !sendBody && review.bodyPublished == nil {
            throw QuicksaveError.message("Requesting changes needs a main comment.")
        }
        let comments = review.unpublished
        var payload: [String: Any] = ["event": event.rawValue,
                                      "comments": comments.map { ["path": $0.path, "line": $0.line, "side": "RIGHT",
                                                                  "body": "\($0.emoji) \($0.text)"] }]
        if sendBody { payload["body"] = body.isEmpty ? legend : body + "\n\n" + legend }
        let file = folder(review.number) + "/publish.json"
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: URL(fileURLWithPath: file))
        if let failed = await GitHub.perform(["api", "--method", "POST", "repos/\(repo)/pulls/\(review.number)/reviews", "--input", file]) {
            throw QuicksaveError.message("GitHub did not take the review: \(failed)")
        }
        return (event, sendBody, comments.map(\.id))
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
            \(done.isEmpty ? "" : "- comments already published, read-only, never return them:\n" + json(done))

            Rules:
            - Return every not-yet-published comment, with its id, changed or not. To drop one, set dropped true. A new comment has no id.
            - A new comment must sit on a line ADDED by the diff: check with `git diff origin/\(review.baseRef)...HEAD -- <file>`. If what he says is about the whole pull request, it goes in the main comment.
            - Never add a link to the emoji legend: Quicksave adds it when he publishes.
            - Turn his words into clean review comments in his voice: English, short, direct, no em-dashes. Keep his meaning, do not add opinions he did not give. The emoji follows the weight he gives it.
            - Change the verdict only if his notes say so or plainly imply it.
            - summary: one sentence on what you changed.

            \(Morning.howToRun)
            """,
            model: "claude-sonnet-5-5",
            allowed: reviewReads,
            denied: reviewNever + ["Edit", "Write"],
            schema: """
            {"type":"object","properties":{"verdict":{"type":"string","enum":["APPROVE","COMMENT","REQUEST_CHANGES"]},"body":{"type":"string"},"comments":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"path":{"type":"string"},"line":{"type":"integer"},"emoji":{"type":"string"},"text":{"type":"string"},"dropped":{"type":"boolean"}},"required":["path","line","emoji","text"]}},"summary":{"type":"string"}},"required":["verdict","body","comments","summary"]}
            """,
            maxTurns: 40,
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
    struct Comment: Decodable { let id: String?; let path: String; let line: Int; let emoji: String; let text: String; let dropped: Bool? }
    let verdict: String
    let body: String
    let comments: [Comment]
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
            let sent = try await Reviews.publish(review)
            let now = Date()
            editReview(number) { r in
                r.verdictPublished = sent.event == .comment && r.verdictPublished != nil ? r.verdictPublished : sent.event
                if sent.body { r.bodyPublished = now }
                for i in r.comments.indices where sent.comments.contains(r.comments[i].id) {
                    r.comments[i].published = now
                    r.comments[i].touched = false
                }
            }
        } catch {
            reviewNotice[number] = error.localizedDescription
        }
    }
}
