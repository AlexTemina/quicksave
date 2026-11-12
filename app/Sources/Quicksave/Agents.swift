import Foundation

/// A job for a Claude agent that runs in the background with nobody to approve its actions: it may do only what
/// its allowed list says. See `docs/background-agents.md`.
struct AgentJob {
    let name: String
    let directory: String
    let prompt: String
    let model: String
    let allowed: [String]
    let denied: [String]
    /// JSON Schema of the result the agent must return.
    let schema: String
    let maxTurns: Int
    /// Folders outside its own it may read, like the vault for the weekly contract.
    var extraDirectories: [String] = []
    /// A past session to continue, so the agent remembers what it read. Always forked: the original stays as it was,
    /// and two drafts of the same session can be talked over at once.
    var resume: String? = nil
}

struct AgentRun {
    let resultJSON: String
    let cost: Double?
    let turns: Int?
    let seconds: Double
    /// Actions the agent tried and was not allowed to do.
    let denials: [String]
    /// The session it ran in, to continue it later.
    let sessionId: String?
}

enum Agents {
    static var claude: String { NSHomeDirectory() + "/.local/bin/claude" }

    /// Runs a job. With `onStep`, the agent's output streams and each action it takes is told as a few words
    /// ("Reading Linear"), so a conversation can show what it is doing while it works.
    static func run(_ job: AgentJob, onStep: (@Sendable (String) -> Void)? = nil) async throws -> AgentRun {
        guard FileManager.default.isExecutableFile(atPath: claude) else {
            throw QuicksaveError.message("Claude Code is not installed where Quicksave looks for it (\(claude)).")
        }
        guard FileManager.default.fileExists(atPath: job.directory) else {
            throw QuicksaveError.message("The folder the \(job.name) job runs in does not exist: \(job.directory)")
        }
        return try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: claude)
            p.currentDirectoryURL = URL(fileURLWithPath: job.directory)
            // Settings of the project only: his global hooks (stop checks, state reporters) are noise for a job.
            // The prompt goes through standard input so the list options cannot swallow it.
            let format: [String] = onStep == nil ? ["--output-format", "json"] : ["--output-format", "stream-json", "--verbose"]
            var args: [String] = ["-p", "--model", job.model, "--permission-mode", "dontAsk", "--setting-sources", "project,local",
                                  "--max-turns", "\(job.maxTurns)"]
            args += format
            args += ["--allowedTools", job.allowed.joined(separator: ","),
                     "--disallowedTools", job.denied.joined(separator: ","),
                     "--json-schema", job.schema]
            args += job.extraDirectories.flatMap { ["--add-dir", $0] }
            if let resume = job.resume { args += ["--resume", resume, "--fork-session"] }
            p.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["CLAUDE_CONFIG_DIR"] = nil
            let home = NSHomeDirectory()
            env["PATH"] = ["/Applications/Orca.app/Contents/Resources/bin", "/opt/homebrew/bin", "/usr/local/bin",
                           home + "/.local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
            p.environment = env

            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            p.standardInput = stdin
            p.standardOutput = stdout
            p.standardError = stderr

            let box = Box()
            let group = DispatchGroup()
            group.enter()
            if let onStep {
                // One JSON event per line: tell each action as it happens, and keep the last line, the result.
                DispatchQueue.global().async {
                    var pending = Data()
                    let handle = stdout.fileHandleForReading
                    while true {
                        let chunk = handle.availableData
                        if chunk.isEmpty { break }
                        pending.append(chunk)
                        while let nl = pending.firstIndex(of: 0x0A) {
                            let line = pending[pending.startIndex..<nl]
                            pending = Data(pending[pending.index(after: nl)...])
                            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                            if obj["type"] as? String == "result" { box.out = Data(line) }
                            else if let step = step(from: obj) { onStep(step) }
                        }
                    }
                    if !pending.isEmpty, box.out.isEmpty { box.out = pending }
                    group.leave()
                }
            } else {
                DispatchQueue.global().async { box.out = stdout.fileHandleForReading.readDataToEndOfFile(); group.leave() }
            }
            group.enter()
            DispatchQueue.global().async { box.err = stderr.fileHandleForReading.readDataToEndOfFile(); group.leave() }

            let started = Date()
            p.terminationHandler = { _ in
                group.notify(queue: .global()) {
                    cont.resume(with: Result { try parse(box.out, box.err, Date().timeIntervalSince(started)) })
                }
            }
            do { try p.run() } catch { cont.resume(throwing: error); return }
            stdin.fileHandleForWriting.write(Data(job.prompt.utf8))
            try? stdin.fileHandleForWriting.close()
        }
    }

    private final class Box: @unchecked Sendable { var out = Data(); var err = Data() }

    /// What a streamed event says the agent is doing, in a few words, or nil when it is nothing to tell.
    static func step(from event: [String: Any]) -> String? {
        guard event["type"] as? String == "assistant",
              let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return nil }
        for part in content.reversed() {
            if part["type"] as? String == "tool_use" {
                let name = part["name"] as? String ?? ""
                let input = part["input"] as? [String: Any] ?? [:]
                return describe(tool: name, input: input)
            }
            if part["type"] as? String == "text", let t = part["text"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Thinking"
            }
        }
        return nil
    }

    private static func describe(tool name: String, input: [String: Any]) -> String {
        let lower = name.lowercased()
        if lower.contains("linear") { return "Reading Linear" }
        if lower.contains("slack") { return "Reading Slack" }
        if lower.contains("calendar") { return "Reading the calendar" }
        if lower.contains("notion") { return "Reading Notion" }
        switch name {
        case "Bash":
            let command = input["command"] as? String ?? ""
            if command.contains("orca linear") { return "Reading Linear" }
            if command.hasPrefix("gh ") || command.contains(" gh ") { return "Reading GitHub" }
            if command.hasPrefix("git ") { return "Looking at the code" }
            return "Running a command"
        case "Read", "Grep", "Glob": return "Reading files"
        case "ToolSearch": return "Finding its tools"
        case "WebFetch", "WebSearch": return "Reading the web"
        case "StructuredOutput": return "Writing the answer"
        default: return "Using \(name)"
        }
    }

    private static func parse(_ out: Data, _ err: Data, _ seconds: Double) throws -> AgentRun {
        let text = String(data: out, encoding: .utf8) ?? ""
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let obj = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any] else {
            let said = String(data: err, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw QuicksaveError.message("The agent returned nothing readable. \(said)")
        }
        if obj["is_error"] as? Bool == true {
            throw QuicksaveError.message((obj["result"] as? String) ?? "The agent stopped with an error.")
        }
        var result = ""
        if let structured = obj["structured_output"], JSONSerialization.isValidJSONObject(structured),
           let data = try? JSONSerialization.data(withJSONObject: structured) {
            result = String(data: data, encoding: .utf8) ?? ""
        } else if let r = obj["result"] as? String {
            result = r.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.hasPrefix("```") {
                result = result.components(separatedBy: "\n").dropFirst().filter { !$0.hasPrefix("```") }.joined(separator: "\n")
            }
        }
        guard !result.isEmpty else { throw QuicksaveError.message("The agent finished without a result.") }
        let denials = (obj["permission_denials"] as? [[String: Any]] ?? []).map { d -> String in
            let tool = d["tool_name"] as? String ?? "tool"
            let command = (d["tool_input"] as? [String: Any])?["command"] as? String
            return command.map { "\(tool): \($0)" } ?? tool
        }
        return AgentRun(resultJSON: result, cost: obj["total_cost_usd"] as? Double, turns: obj["num_turns"] as? Int,
                        seconds: seconds, denials: denials, sessionId: obj["session_id"] as? String)
    }
}

extension AgentJob {
    /// Executes everything Alejandro approved in the inbox: what the vault's `/auditor apply` does, started by hand.
    static func apply() -> AgentJob {
        AgentJob(
            name: "apply",
            directory: NSHomeDirectory() + "/orca/workspaces/vault/auditor-apply-2",
            prompt: """
            You are running /auditor apply as a manual run started from Quicksave, right after Alejandro decided cards in the Quicksave inbox.

            Read Claude/commands/auditor.md and follow its `apply` section, with these differences:
            - This is not the scheduled run. Do not read ~/.cache/auditor-apply/candidates.json, it is stale. Use the live Linear queries of step 1 and handle every item of the Auditor project that is in state Todo.
            - Accepting a card approves everything it names, including closing or moving to Done the issues it lists. If he corrected a card, his edited text is in its description: execute that text, it overrides the original proposal.
            - Execute each item, then move it to Done. Anything you cannot finish (an action was denied, it is ambiguous, it needs his decision): move it to Pending for inputs and say why in your result.
            - Never post anything anywhere: no comments, no messages. Anything that would post text becomes a draft in your result.
            - Do not send Telegram, and do not run any sweep or watermark step.
            - Do not touch items in any other state.
            - If an item is code work in a git worktree of another repository (a rebase, a fix, running tests in a worktree of alan-apps), do not try it and do not change its state. Return outcome needs_worktree with `worktree` set to the worktree's folder name and `task` set to one self-contained paragraph saying what to do there. Another agent will do it inside that worktree.
            - An issue you create from an accepted card goes straight to Todo with a due date. Never leave it in Triage: it would come back to him as a new card.
            - Your result must list every item that was in Todo when you started, even one that was trivial.

            How to run commands, because you work with a short list of allowed actions and anything that does not match it is refused:
            - To edit or create a Linear issue, use the Linear tools (save_issue). Do not build files in /tmp or shell scripts for it.
            - For anything in a shell, run one simple command per call. No `cd` (you are already in the right folder), no `&&` or `;`, no pipes, no heredocs, no redirections.

            Return the structured result, written in English:
            - One entry per item you handled. Its summary is one or two short sentences: what you did, or what stopped you.
            - Every draft: `where` is exactly one of Linear, Slack, GitHub, Mail or Other; `note` says in one line what to do with it; `text` is only the text to paste. For a Slack draft, set `link` to the Slack URL of the channel or thread where it goes, found with the Slack channel search; leave it empty only if you could not find it. Set `item` to the code of the Todo item the draft came from.
            - `notes`: only what he must act on, in one or two sentences, or empty. Do not report technical steps you skipped.
            """,
            model: "claude-sonnet-5-5",
            allowed: ["Read", "Grep", "Glob", "Edit", "Write", "ToolSearch",
                      "mcp__claude_ai_Linear__save_issue", "mcp__claude_ai_Linear__get_issue", "mcp__claude_ai_Linear__list_issues",
                      "mcp__claude_ai_Linear__list_comments", "mcp__claude_ai_Linear__list_issue_statuses",
                      "mcp__claude_ai_Linear__list_projects", "mcp__claude_ai_Linear__get_project", "mcp__claude_ai_Linear__save_project",
                      "mcp__claude_ai_Slack__slack_search_channels",
                      "Bash(orca linear:*)", "Bash(orca worktree:*)",
                      "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git fetch:*)",
                      "Bash(git add:*)", "Bash(git commit:*)", "Bash(git push:*)",
                      "Bash(gh pr view:*)", "Bash(gh pr list:*)", "Bash(date:*)"],
            denied: ["Bash(orca linear comment:*)", "Bash(orca worktree rm:*)",
                     "Bash(git push --force:*)", "Bash(git push -f:*)", "Bash(git reset --hard:*)", "Bash(rm:*)",
                     "mcp__claude_ai_Slack__slack_send_message", "mcp__claude_ai_Slack__slack_schedule_message",
                     "mcp__claude_ai_Gmail__send_message", "mcp__claude_ai_Gmail__reply", "mcp__claude_ai_Gmail__forward",
                     "mcp__claude_ai_Linear__save_comment"],
            schema: """
            {"type":"object","properties":{"items":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"outcome":{"type":"string","enum":["done","needs_you","failed","skipped","needs_worktree"]},"summary":{"type":"string"},"links":{"type":"array","items":{"type":"string"}},"worktree":{"type":"string"},"task":{"type":"string"}},"required":["id","outcome","summary"]}},"drafts":{"type":"array","items":{"type":"object","properties":{"where":{"type":"string","enum":["Linear","Slack","GitHub","Mail","Other"]},"note":{"type":"string"},"link":{"type":"string"},"item":{"type":"string"},"text":{"type":"string"}},"required":["where","text"]}},"notes":{"type":"string"}},"required":["items","drafts"]}
            """,
            maxTurns: 80)
    }
}

extension AgentJob {
    /// Does one task of code inside a git worktree: rebases, fixes, tests. It never publishes: pushing is his next step.
    static func worktree(item: String, directory: String, task: String, comment: String) -> AgentJob {
        AgentJob(
            name: "worktree \(item)",
            directory: directory,
            prompt: """
            You are working on behalf of Alejandro inside this git worktree, which is the current folder. Quicksave started you after he accepted the card \(item).

            Task: \(task)

            What Orca keeps as the comment of this worktree (what he or an earlier agent left here): \(comment.isEmpty ? "nothing" : comment)

            Rules:
            - Work only inside this folder. Read its own instructions (AGENTS.md) for how to run things here.
            - Start by looking: git status, a fetch, and how the branch relates to its remote and to origin/main. If anything looks unexpected (uncommitted changes you did not make, a branch far from where the task assumes), change nothing and report needs_you with what you saw.
            - A branch that has diverged from its remote is normal after a rebase. If the comment above says it was rebased locally, the local branch is the authoritative one: do not reset it onto the remote and do not ask which one is right. Check only what the task needs, and say what is left for him.
            - If `git fetch origin` fails because of an unrelated stale reference, fetch only what you need, for example `git fetch origin main`, and carry on.
            - Never push, never open or edit a pull request, never post a comment or a message. If publishing is needed, that is his next step: say so.
            - Never discard work: no reset --hard, no clean, no deleting files beyond what the task needs.
            - One simple command per call: no `cd`, no `&&` or `;`, no pipes, no heredocs.
            - If a command is refused, do not look for a way around it: say what you could not do.

            Return the structured result, written in English: outcome (done when the task is finished, needs_you when he must decide or do something, failed when you could not do it), summary in one or two sentences, tests (what you ran and the result, or "not run"), nextStep (what he does next, one sentence) and branch.
            """,
            model: "claude-sonnet-5-5",
            allowed: ["Read", "Grep", "Glob", "Edit", "Write",
                      "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)", "Bash(git fetch:*)",
                      "Bash(git branch:*)", "Bash(git rev-parse:*)", "Bash(git merge-base:*)",
                      "Bash(git add:*)", "Bash(git commit:*)", "Bash(git rebase:*)",
                      "Bash(alan run:*)", "Bash(uv run:*)", "Bash(pytest:*)", "Bash(python -m pytest:*)", "Bash(date:*)"],
            denied: ["Bash(git push:*)", "Bash(git reset --hard:*)", "Bash(git clean:*)", "Bash(rm:*)", "Bash(gh:*)",
                     "mcp__claude_ai_Slack__slack_send_message", "mcp__claude_ai_Gmail__send_message",
                     "mcp__claude_ai_Linear__save_comment"],
            schema: """
            {"type":"object","properties":{"outcome":{"type":"string","enum":["done","needs_you","failed"]},"summary":{"type":"string"},"tests":{"type":"string"},"nextStep":{"type":"string"},"branch":{"type":"string"}},"required":["outcome","summary","tests","nextStep"]}
            """,
            maxTurns: 120)
    }
}

extension AgentJob {
    /// Leaves a text as a draft in his own Slack. It may search channels and people and create the draft, nothing else:
    /// it can never send or schedule a message.
    static func slackDraft(text: String, note: String, link: String?) -> AgentJob {
        AgentJob(
            name: "slack draft",
            directory: NSTemporaryDirectory(),
            prompt: """
            Create a draft in Slack for Alejandro. A draft is saved in his own "Drafts & Sent" and is never sent: he reads it and sends it himself.

            The text of the draft. Use it as it is, only turning a person's name into a mention when the note says to tag them:
            <<<
            \(text)
            >>>

            What to do with it: \(note.isEmpty ? "nothing more" : note)
            Where it goes, if known: \(link ?? "not known")

            How:
            - Find the channel with the Slack search tools. For a direct message to a person, find the person and use their user id as the channel. For a reply in a thread whose link you have, use thread_ts.
            - If the note says it is a reply in a thread and you have no link, find the thread: read the channel's recent messages (or search it) for the parent the note names, and use its ts as thread_ts. For the standup, the parent is today's message titled "Spain Area Standup" in #area_spain.
            - The Slack tools are deferred: find them first with ToolSearch (for example select:mcp__claude_ai_Slack__slack_read_channel), then call them.
            - If you cannot tell which channel, or several are plausible, do not guess: create nothing and return needs_you saying why in one sentence.
            - Slack allows one draft per channel. If it says a draft already exists there (attached_draft_exists), return needs_you with this sentence: "There is already a draft in <channel name>. Delete it in Slack, under Drafts & Sent, and try again." Put the channel's link in `link`.
            - Never send a message and never schedule one. Only create the draft.

            Return the structured result, written in English: outcome (drafted, needs_you or failed), summary in one sentence, and link with the Slack URL of the channel where the draft is, if you have it.
            """,
            model: "claude-sonnet-5-5",
            allowed: ["ToolSearch", "mcp__claude_ai_Slack__slack_send_message_draft", "mcp__claude_ai_Slack__slack_search_channels",
                      "mcp__claude_ai_Slack__slack_search_users", "mcp__claude_ai_Slack__slack_read_channel",
                      "mcp__claude_ai_Slack__slack_read_thread", "mcp__claude_ai_Slack__slack_search_public_and_private"],
            denied: ["mcp__claude_ai_Slack__slack_send_message", "mcp__claude_ai_Slack__slack_schedule_message",
                     "mcp__claude_ai_Gmail__send_message", "mcp__claude_ai_Linear__save_comment", "Bash(rm:*)"],
            schema: """
            {"type":"object","properties":{"outcome":{"type":"string","enum":["drafted","needs_you","failed"]},"summary":{"type":"string"},"link":{"type":"string"}},"required":["outcome","summary"]}
            """,
            maxTurns: 15)
    }
}

extension AgentJob {
    /// Rewrites a draft following his instruction. With context it may read where the draft came from, only to get the
    /// facts right. It returns text and nothing else: it can never post, send or save.
    static let draftContextTools = ["ToolSearch", "mcp__claude_ai_Linear__get_issue", "mcp__claude_ai_Linear__list_comments",
                                    "mcp__claude_ai_Slack__slack_read_channel", "mcp__claude_ai_Slack__slack_read_thread",
                                    "mcp__claude_ai_Slack__slack_search_users", "mcp__claude_ai_Slack__slack_search_channels"]
    static let draftNever = ["mcp__claude_ai_Slack__slack_send_message", "mcp__claude_ai_Slack__slack_send_message_draft",
                             "mcp__claude_ai_Slack__slack_schedule_message", "mcp__claude_ai_Gmail__send_message",
                             "mcp__claude_ai_Linear__save_issue", "mcp__claude_ai_Linear__save_comment",
                             "mcp__claude_ai_Linear__save_status_update", "Edit", "Write", "Bash(rm:*)"]

    /// One turn of the conversation about a draft. When the draft keeps the session of the agent that wrote it, that
    /// session continues and remembers everything it read; otherwise a new agent starts with the conversation so far.
    /// `text` is the version being talked about: the last one proposed, even if he has not used it yet.
    static func draftTalk(_ draft: DraftItem, text: String, history: [DraftTurn], message: String) -> AgentJob {
        let resumed = draft.session != nil
        let rules = """
        Rules:
        - If his message is clear enough, return `text`: the complete new text, ready to paste, not a diff. And `notes`: one short sentence on what you changed.
        - If you need something from him to do it right (a fact, a choice), return `question` instead, one short question, and no `text`.
        - Keep the format of the place. Slack text is plain Markdown with no headings; Linear, GitHub and mail text is Markdown. Keep links and mentions unless he asks to change them.
        - English, no em-dashes, short direct sentences, every code with a 2-3 word tag.
        - Do not invent facts. Read only what his message needs. Deferred tools: find them first with ToolSearch.
        - Never post, send or save anything anywhere: not in Linear, Slack or the vault. You only return text.
        """
        let current = """
        The text as it is now (he may have edited it by hand):
        <<<
        \(text)
        >>>

        His message: \(message)
        """
        let prompt: String
        if resumed {
            prompt = """
            Alejandro is reviewing one of the drafts you returned in this session, the one with the note "\(draft.note)", and talks to you about it. Work only on that draft.

            \(current)

            \(rules)
            """
        } else {
            let past = history.compactMap { t -> String? in
                switch t.who {
                case .me: return "He said: " + t.text
                case .agent: return t.body == nil ? "You asked: " + t.text : "You rewrote it: " + t.text
                default: return nil
                }
            }
            prompt = """
            You help Alejandro polish a draft he will post himself, talking with him about it.

            Draft for: \(draft.place)\(draft.link.map { " (\($0.absoluteString))" } ?? "")
            What to do with it: \(draft.note.isEmpty ? "nothing more" : draft.note)
            It came from: \(draft.item.isEmpty ? draft.source : draft.item)
            \(past.isEmpty ? "" : "\nThe conversation so far:\n" + past.joined(separator: "\n") + "\n")
            \(current)

            \(rules)
            - You may read where the draft came from, only to get facts right: the item above in Linear, the Slack channel or thread behind the link.
            """
        }
        let ritual = Ritual(rawValue: draft.source) != nil
        return AgentJob(
            name: "draft talk",
            directory: draft.sessionDir ?? NSTemporaryDirectory(),
            prompt: prompt,
            model: "claude-sonnet-5-5",
            allowed: ritual ? ritualReads : draftContextTools,
            denied: ritual ? ritualNever : draftNever,
            schema: """
            {"type":"object","properties":{"text":{"type":"string"},"question":{"type":"string"},"notes":{"type":"string"}}}
            """,
            maxTurns: 40,
            resume: draft.session)
    }
}

extension AgentJob {
    /// /start-task for an issue that has no agent yet, run unattended from the vault: it creates the alan-apps worktree
    /// and the agent tab named after the issue, in Orca, where he takes over. Not code work: no worktree, and the app
    /// opens the agent itself.
    /// Carries out what he said to do with one of his expired issues: reassign it, move it, split it… in Linear only.
    /// A message to someone is returned as a draft, never sent.
    static func issueInstruction(id: String, title: String, url: String, instruction: String) -> AgentJob {
        AgentJob(
            name: "instruction \(id)",
            directory: Morning.repo,
            prompt: """
            Alejandro looked at one of his overdue Linear issues in Quicksave and said what to do with it. Do exactly that, in Linear, and nothing more.

            The issue: \(id) "\(title)" (\(url))
            What he said:
            <<<
            \(instruction)
            >>>

            Rules:
            - Read the issue first: `orca linear issue \(id) --relations --json`.
            - Change only what he asked: assignee, state, due date, priority, project, labels, relations or description. To find a person, use the Linear users tools (list_users, get_user) and pick the one he means; if two fit, do nothing and return needs_you naming both.
            - A description is written to a file first, with the Write tool, in "\(Morning.scratch)/", then passed with --body-file (quotes matter, the folder has a space).
            - Never post a comment, never send a message. If telling someone is part of what he asked (or plainly needed, like a reassignment to a person who does not know yet), return a draft: where (Slack or Linear), note (who and why), link (the Slack thread or issue it belongs to, if any) and text, in English, short, no em-dashes, every code with a 2-3 word tag.
            - If a write answers linear_write_unconfirmed, retry it with its --write-id.
            - Read the issue back at the end to check what changed.

            Commands: `orca linear save-issue \(id) --assignee <user> --state <state> --due-date <yyyy-mm-dd|null> --priority <none|low|medium|high|urgent> --project <project|null> --body-file <path> --json` (only the flags you need), `orca linear relation add|remove`, `orca linear label add|remove`. If one fails, read its --help once and retry.

            \(Morning.howToRun)

            Return: outcome (done, needs_you or failed), summary (one or two sentences in English saying what changed), drafts.
            """,
            model: "claude-sonnet-5-5",
            allowed: ["Read", "ToolSearch", "Bash(date:*)", "Write(/\(Morning.scratch)/**)",
                      "mcp__claude_ai_Linear__list_users", "mcp__claude_ai_Linear__get_user",
                      "Bash(orca linear save-issue:*)", "Bash(orca linear relation add:*)", "Bash(orca linear relation remove:*)",
                      "Bash(orca linear label add:*)", "Bash(orca linear label remove:*)"] + Morning.readLinear,
            denied: Morning.neverPost + ["mcp__claude_ai_Slack__slack_send_message_draft"],
            schema: """
            {"type":"object","properties":{"outcome":{"type":"string","enum":["done","needs_you","failed"]},"summary":{"type":"string"},"drafts":{"type":"array","items":{"type":"object","properties":{"where":{"type":"string"},"note":{"type":"string"},"link":{"type":"string"},"text":{"type":"string"}},"required":["where","text"]}}},"required":["outcome","summary"]}
            """,
            maxTurns: 30,
            extraDirectories: [Morning.scratch])
    }

    static func startTask(id: String) -> AgentJob {
        AgentJob(
            name: "start task \(id)",
            directory: NSHomeDirectory() + "/vault",
            prompt: """
            Run /start-task \(id) as an unattended run started from Quicksave: Alejandro pressed Start on the issue's card.

            Read Claude/commands/start-task.md and follow steps 1 to 5. Differences:
            - Skip step 5b (the Daily) and step 6 (the report): return the structured result instead.
            - If the issue is not code work in alan-apps (admin, writing, a decision, a vault task, a review that needs no checkout), create no worktree and open no agent: return no_worktree. Quicksave then opens an agent in the vault itself.
            - If a worktree already links the issue, reuse it (step 2) and still open the agent of step 4 if none is there.
            - Never post anything and never commit.

            How to run commands, because you work with a short list of allowed actions:
            - One simple command per call. No `cd`, no `&&` or `;`, no pipes, no heredocs.
            - The Linear tools are deferred: find them with ToolSearch first if you need them.

            Return: outcome (created, reused, no_worktree or failed), worktreePath, terminal (the handle `orca terminal create` gave), and summary in one sentence, in English.
            """,
            model: "claude-sonnet-5-5",
            allowed: ["Read", "Grep", "Glob", "ToolSearch", "mcp__claude_ai_Linear__get_issue",
                      "Bash(orca linear issue:*)", "Bash(orca linear search:*)", "Bash(orca linear status set:*)",
                      "Bash(orca worktree list:*)", "Bash(orca worktree show:*)", "Bash(orca worktree create:*)", "Bash(orca worktree set:*)",
                      "Bash(orca terminal list:*)", "Bash(orca terminal create:*)", "Bash(orca terminal wait:*)",
                      "Bash(orca terminal send:*)", "Bash(orca terminal rename:*)", "Bash(orca terminal switch:*)", "Bash(date:*)"],
            denied: ["Bash(orca linear comment:*)", "Bash(orca worktree rm:*)", "Bash(git push:*)", "Bash(git commit:*)", "Bash(rm:*)",
                     "mcp__claude_ai_Linear__save_comment", "mcp__claude_ai_Slack__slack_send_message"],
            schema: """
            {"type":"object","properties":{"outcome":{"type":"string","enum":["created","reused","no_worktree","failed"]},"worktreePath":{"type":"string"},"terminal":{"type":"string"},"summary":{"type":"string"}},"required":["outcome","summary"]}
            """,
            maxTurns: 40)
    }
}

struct InstructionResult: Decodable {
    struct DraftOut: Decodable {
        let place: String
        let note: String?
        let link: String?
        let text: String
        enum CodingKeys: String, CodingKey { case place = "where", note, link, text }
    }
    let outcome: String
    let summary: String
    let drafts: [DraftOut]?
}

struct StartTaskResult: Decodable {
    let outcome: String
    let worktreePath: String?
    let terminal: String?
    let summary: String
}

struct DraftTalkResult: Decodable {
    let text: String?
    let question: String?
    let notes: String?
}

struct SlackDraftResult: Decodable {
    let outcome: String
    let summary: String
    let link: String?
}

struct WorktreeAgentResult: Decodable {
    let outcome: String
    let summary: String
    let tests: String
    let nextStep: String
    let branch: String?
}

/// The shape of what the apply agent returns.
struct ApplyAgentResult: Decodable {
    struct Item: Decodable {
        let id: String
        let outcome: String
        let summary: String
        let links: [String]?
        let worktree: String?
        let task: String?
    }
    struct DraftOut: Decodable {
        let place: String
        let note: String?
        let link: String?
        let item: String?
        let text: String
        enum CodingKeys: String, CodingKey { case place = "where", note, link, item, text }
    }
    let items: [Item]
    let drafts: [DraftOut]
    let notes: String?
}
