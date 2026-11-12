import AppKit
import Foundation

/// Jump from a Linear issue to its Orca worktree. Orca owns the mapping: `orca reference find <issue>`
/// returns the worktrees linked to the issue and their agents. Rules, in order:
/// 1. A live agent in a linked worktree: bring that agent's tab forward.
/// 2. A linked worktree without a live agent: bring its first open terminal forward, or open a new one there.
/// 3. No linked worktree: nothing to jump to (the button is off).
enum Orca {
    struct Match { let worktreeId: String; let name: String; let liveAgentTerminal: String? }

    static let binary = "/Applications/Orca.app/Contents/Resources/bin/orca"

    static func worktree(for issue: String) async -> Match? {
        guard let data = try? await run(["reference", "find", issue, "--json"]) else { return nil }
        struct Env: Decodable {
            struct R: Decodable {
                struct M: Decodable {
                    struct W: Decodable { let id: String; let name: String; let archived: Bool? }
                    struct A: Decodable { let terminal: String?; let liveness: String? }
                    let workspace: W
                    let agents: [A]?
                }
                let matches: [M]
            }
            let result: R
        }
        let matches = ((try? JSONDecoder().decode(Env.self, from: data))?.result.matches ?? []).filter { $0.workspace.archived != true }
        if let pick = matches.first(where: { $0.agents?.contains { $0.liveness == "live" } == true }) ?? matches.first {
            return Match(worktreeId: pick.workspace.id, name: pick.workspace.name,
                         liveAgentTerminal: pick.agents?.first { $0.liveness == "live" }?.terminal)
        }
        // No linked worktree: an agent tab named after the issue still counts, wherever it runs.
        if let t = await namedAgent(issue) {
            return Match(worktreeId: t.worktreeId, name: (t.worktreePath as NSString).lastPathComponent, liveAgentTerminal: t.handle)
        }
        return nil
    }

    struct Terminal: Decodable {
        let handle: String
        let title: String?
        let connected: Bool?
        let worktreeId: String
        let worktreePath: String
        let agentIdentity: String?
    }

    /// The agent tab whose title starts with the issue's code, as /start-task names it ("ES-12867 — …").
    static func namedAgent(_ issue: String) async -> Terminal? {
        struct Env: Decodable { struct R: Decodable { let terminals: [Terminal] }; let result: R }
        guard let data = try? await run(["terminal", "list", "--json"]),
              let all = (try? JSONDecoder().decode(Env.self, from: data))?.result.terminals else { return nil }
        return all.first { t in
            guard t.connected != false, t.agentIdentity != nil, let title = t.title else { return false }
            return title.hasPrefix(issue + " ") || title == issue
        }
    }

    /// Opens a new Claude agent in Orca, in auto mode, names its tab after the issue and gives it its first prompt.
    static func startAgent(in folder: String, title: String, prompt: String) async throws {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Orca.app"))
        struct Env: Decodable { struct R: Decodable { struct T: Decodable { let handle: String }; let terminal: T }; let result: R }
        let created = try await run(["terminal", "create", "--worktree", "path:\(folder)", "--command", "claude --permission-mode auto",
                                     "--title", title, "--focus", "--json"])
        guard let handle = (try? JSONDecoder().decode(Env.self, from: created))?.result.terminal.handle else {
            throw QuicksaveError.message("Orca did not open the agent's terminal.")
        }
        _ = try? await run(["terminal", "wait", "--terminal", handle, "--for", "tui-idle", "--timeout-ms", "120000", "--json"])
        // Claude retitles its tab from the session name, so the session itself is named after the issue too.
        _ = try? await run(["terminal", "send", "--terminal", handle, "--text", "/rename \(title)", "--enter", "--json"])
        _ = try? await run(["terminal", "send", "--terminal", handle, "--text", prompt, "--enter", "--json"])
        _ = try? await run(["terminal", "rename", "--terminal", handle, "--title", title, "--json"])
    }

    /// Types a message into an agent's terminal and sends it, as if he had written it there.
    static func send(terminal handle: String, text: String) async -> Bool {
        (try? await run(["terminal", "send", "--terminal", handle, "--text", text, "--enter", "--json"])) != nil
    }

    static func focus(terminal handle: String) async {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Orca.app"))
        _ = try? await run(["terminal", "switch", "--terminal", handle, "--json"])
    }

    /// Closes an agent's terminal in Orca, which ends its session. The worktree and its files stay as they are; other
    /// terminals in the same worktree stay open.
    static func close(terminal handle: String) async throws {
        _ = try await run(["terminal", "close", "--terminal", handle, "--json"])
    }

    static func go(to match: Match) async throws {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Orca.app"))
        if let terminal = match.liveAgentTerminal {
            _ = try await run(["terminal", "switch", "--terminal", terminal, "--json"]); return
        }
        struct Env: Decodable { struct R: Decodable { struct T: Decodable { let handle: String; let connected: Bool? }; let terminals: [T] }; let result: R }
        let listed = try await run(["terminal", "list", "--worktree", "id:\(match.worktreeId)", "--json"])
        if let first = (try? JSONDecoder().decode(Env.self, from: listed))?.result.terminals.first(where: { $0.connected != false }) {
            _ = try await run(["terminal", "switch", "--terminal", first.handle, "--json"])
        } else {
            _ = try await run(["terminal", "create", "--worktree", "id:\(match.worktreeId)", "--focus", "--json"])
        }
    }

    struct Worktree { let id: String; let name: String; let path: String; let comment: String }

    /// A worktree by its name: where it lives and the comment Orca keeps for it.
    static func worktree(named name: String) async -> Worktree? {
        guard let data = try? await run(["worktree", "show", "--worktree", "name:\(name)", "--json"]) else { return nil }
        struct Env: Decodable {
            struct R: Decodable {
                struct W: Decodable { let id: String; let path: String; let displayName: String?; let comment: String? }
                let worktree: W
            }
            let result: R
        }
        guard let w = (try? JSONDecoder().decode(Env.self, from: data))?.result.worktree else { return nil }
        return Worktree(id: w.id, name: w.displayName ?? name, path: w.path, comment: w.comment ?? "")
    }

    /// Replaces the worktree's comment in Orca, where the summary of what an agent did is kept.
    static func setComment(worktreeId: String, _ text: String) async {
        _ = try? await run(["worktree", "set", "--worktree", "id:\(worktreeId)", "--comment", text, "--json"])
    }

    /// Writes to Linear through Orca (`orca linear ...`), which reaches the Alan workspace with the write access
    /// Quicksave's own read-only key does not have. Throws with Orca's own message when Linear refuses.
    ///
    /// A write Orca could not confirm (`linear_write_unconfirmed`) is handled as Orca asks: with a write id it is
    /// retried once with it; without one, `landed` reads Linear back to tell whether the change is there.
    static func linearWrite(_ args: [String], landed: (() async -> Bool)? = nil) async throws {
        struct Env: Decodable {
            struct E: Decodable { struct D: Decodable { let writeId: String? }; let code: String?; let message: String?; let data: D? }
            let ok: Bool?; let error: E?
        }
        func attempt(_ extra: [String]) async throws -> Env? {
            let data = try await output(["linear"] + args + extra + ["--json"])
            return try? JSONDecoder().decode(Env.self, from: data)
        }
        var env = try await attempt([])
        if env?.ok != false { return }
        if env?.error?.code == "linear_write_unconfirmed" {
            if let writeId = env?.error?.data?.writeId {
                env = try await attempt(["--write-id", writeId])
                if env?.ok != false { return }
            }
            if let landed, await landed() { return }
        }
        throw QuicksaveError.message(env?.error?.message ?? "Linear refused the change")
    }

    /// What Orca printed, even when it exits with an error: its JSON says what went wrong.
    private static func output(_ args: [String]) async throws -> Data {
        try await Shell.run(binary, args).out
    }

    static func run(_ args: [String]) async throws -> Data {
        let r = try await Shell.run(binary, args)
        if r.status == 0 { return r.out }
        let problem = String(data: r.err, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var message = problem.isEmpty ? (String(data: r.out, encoding: .utf8) ?? "") : problem
        if message.count > 300 { message = String(message.prefix(300)) + "…" }
        throw QuicksaveError.message(message.isEmpty ? "orca \(args.prefix(2).joined(separator: " ")) failed" : message)
    }

    /// What an agent is doing, as Orca tracks it. Orca's states: working, blocked (it waits for a permission or an
    /// answer), done (its turn ended: it waits for him), error, idle.
    struct AgentState: Equatable {
        let state: String
        let name: String
        let lastMessage: String
        let updatedAt: Double
        /// Where the agent runs and its terminal, so the card's Orca button goes straight to it.
        var worktreeId = ""
        var worktreeName = ""
        var terminal: String?
        var repo = ""
        /// It runs in a repository's main checkout, not in a worktree of its own.
        var isMain = false
        /// Where it runs, as a person reads it: "vault main", "alan-apps · ES-12986-mo-mobile-prs".
        var place: String { isMain ? repo + " main" : repo + " · " + worktreeName }

        /// Tells two live agents apart.
        var key: String { worktreeId + "|" + (terminal ?? name) }

        var match: Match? {
            worktreeId.isEmpty ? nil : Match(worktreeId: worktreeId, name: worktreeName, liveAgentTerminal: terminal)
        }
    }

    /// The agent of every issue, from one `orca worktree ps`: the agents of the worktree linked to the issue, and any
    /// agent whose conversation is named after it ("ES-12867 — …"). With several, the busiest and most recent wins.
    static func agentStates() async -> [String: AgentState] { await allAgents().byIssue }

    /// Every live agent: the ones named after an issue, by issue, and the rest, which no issue names. The vault's fixed
    /// automation worktrees (🚫) are left out.
    static func allAgents() async -> (byIssue: [String: AgentState], unlinked: [AgentState]) {
        guard let data = try? await run(["worktree", "ps", "--json"]),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let worktrees = (obj["result"] as? [String: Any])?["worktrees"] as? [[String: Any]] else { return ([:], []) }
        let code = try! NSRegularExpression(pattern: #"^([A-Z]+-\d+)\b"#)
        func issue(in text: String) -> String? {
            let ns = text as NSString
            return code.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        }
        let rank = ["blocked": 4, "error": 3, "working": 2, "done": 1, "monitoring": 1]
        let handles = await terminalHandles()
        var out: [String: AgentState] = [:]
        var unlinked: [AgentState] = []
        for w in worktrees where (w["isArchived"] as? Bool) != true {
            var linked: String?
            if let l = w["linkedLinearIssue"] as? String { linked = l }
            else if let l = w["linkedLinearIssue"] as? [String: Any] { linked = l["identifier"] as? String }
            for a in w["agents"] as? [[String: Any]] ?? [] {
                // Orca keeps the record of agents long closed; only one with an open terminal counts.
                let handle = (a["paneKey"] as? String).flatMap { handles[$0] }
                guard (a["hasLivePty"] as? Bool) == true || handle != nil else { continue }
                let name = (a["conversationName"] as? String) ?? (a["taskTitle"] as? String) ?? (a["displayName"] as? String) ?? ""
                let id = issue(in: name) ?? linked.flatMap({ issue(in: $0) }) ?? issue(in: w["displayName"] as? String ?? "")
                // "working" while "monitoring" means its turn ended and it only watches a background task it left running:
                // it is not thinking, and its last message is for him (ES-12279 breathed yellow for minutes, 9-nov).
                var raw = a["state"] as? String ?? "idle"
                if raw == "working", (a["workingMode"] as? String) == "monitoring" { raw = "monitoring" }
                // Orca also says "waiting" when the agent stops on a permission prompt or a question (the plan of
                // ES-12991 asked to overwrite a file and went grey, 10-nov): it is the same as blocked.
                if raw == "waiting" || ((a["programStatus"] as? [String: Any])?["state"] as? String) == "blocked" { raw = "blocked" }
                let state = AgentState(state: raw, name: name,
                                       lastMessage: a["lastAssistantMessage"] as? String ?? "",
                                       updatedAt: a["updatedAt"] as? Double ?? 0,
                                       worktreeId: w["worktreeId"] as? String ?? "",
                                       worktreeName: w["displayName"] as? String ?? "",
                                       terminal: handle,
                                       repo: w["repo"] as? String ?? "",
                                       isMain: (w["isMainWorktree"] as? Bool) == true)
                guard let id else {
                    if !(w["displayName"] as? String ?? "").hasPrefix("🚫") { unlinked.append(state) }
                    continue
                }
                if let old = out[id], (rank[old.state] ?? 0, old.updatedAt) >= (rank[state.state] ?? 0, state.updatedAt) { continue }
                out[id] = state
            }
        }
        return (out, unlinked.sorted { $0.updatedAt > $1.updatedAt })
    }

    /// A worktree open in Orca, as the board's "open, not planned" cards read it.
    struct OpenWorktree: Identifiable, Hashable {
        let id: String
        let name: String
        let repo: String
        /// The Linear issue it works on: the one Orca links, else the code its name or branch starts with, else its
        /// parent's, else the code its live agent's conversation starts with.
        let issue: String?
        /// What its agent last wrote as progress in Orca.
        let comment: String
        /// Set when this is one agent, not a whole worktree: an agent in a main checkout named after an issue.
        var agentTerminal: String? = nil
        var worktreeId: String? = nil

        var isAgent: Bool { worktreeId != nil }
        var match: Match { Match(worktreeId: worktreeId ?? id, name: name, liveAgentTerminal: agentTerminal) }
    }

    /// Everything he has open in Orca that belongs to an issue, so nothing open escapes the board:
    /// - every worktree: not archived, not a repository's main checkout, and not the fixed worktrees of the vault's
    ///   automations (named with 🚫);
    /// - every live agent whose conversation is named after an issue ("ES-12986 — …") when the worktree it runs in
    ///   does not already stand for that issue, as in the vault's or alan-apps' main checkout.
    /// Agents in a main checkout with no issue in their name are left out.
    static func openWorktrees() async -> [OpenWorktree] {
        guard let data = try? await run(["worktree", "ps", "--json"]),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let all = (obj["result"] as? [String: Any])?["worktrees"] as? [[String: Any]] else { return [] }
        let code = try! NSRegularExpression(pattern: #"^([A-Za-z]+-\d+)(?:\b|-)"#)
        func issue(in text: String?) -> String? {
            guard let text else { return nil }
            let ns = text as NSString
            return code.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)).uppercased() }
        }
        func own(_ w: [String: Any]) -> String? {
            if let l = w["linkedLinearIssue"] as? String { return l }
            if let l = (w["linkedLinearIssue"] as? [String: Any])?["identifier"] as? String { return l }
            let branch = (w["branch"] as? String).map { ($0 as NSString).lastPathComponent }
            return issue(in: w["displayName"] as? String) ?? issue(in: branch)
        }
        let handles = await terminalHandles()
        /// Live agents of a worktree, with the issue their conversation is named after.
        func liveAgents(_ w: [String: Any]) -> [(issue: String, name: String, message: String, handle: String?, pane: String)] {
            (w["agents"] as? [[String: Any]] ?? []).compactMap { a in
                let pane = a["paneKey"] as? String ?? ""
                let handle = handles[pane]
                guard (a["hasLivePty"] as? Bool) == true || handle != nil else { return nil }
                let name = (a["conversationName"] as? String) ?? (a["taskTitle"] as? String) ?? (a["displayName"] as? String) ?? ""
                guard let id = issue(in: name) else { return nil }
                return (id, name, a["lastAssistantMessage"] as? String ?? "", handle, pane)
            }
        }
        let byId = Dictionary(all.compactMap { w in (w["worktreeId"] as? String).map { ($0, w) } }, uniquingKeysWith: { a, _ in a })
        var out: [OpenWorktree] = []
        for w in all {
            let name = w["displayName"] as? String ?? ""
            guard (w["isArchived"] as? Bool) != true, !name.hasPrefix("🚫"), let id = w["worktreeId"] as? String else { continue }
            let main = (w["isMainWorktree"] as? Bool) == true
            let agents = liveAgents(w)
            var standsFor: String?
            if !main {
                let parent = (w["parentWorktreeId"] as? String).flatMap { byId[$0] }
                standsFor = own(w) ?? parent.flatMap(own) ?? agents.first?.issue
                out.append(OpenWorktree(id: id, name: name, repo: w["repo"] as? String ?? "",
                                        issue: standsFor, comment: w["comment"] as? String ?? ""))
            }
            for a in agents where a.issue != standsFor {
                let firstLine = a.message.split(separator: "\n").first.map(String.init) ?? ""
                out.append(OpenWorktree(id: id + "#" + a.pane, name: a.name, repo: (w["repo"] as? String ?? "") + (main ? " main" : " · " + name),
                                        issue: a.issue, comment: String(firstLine.prefix(160)),
                                        agentTerminal: a.handle, worktreeId: id))
            }
        }
        return out
    }

    /// Orca names an agent's pane "<tab>:<leaf>"; the terminal list gives the handle for each.
    static func terminalHandles() async -> [String: String] {
        var handles: [String: String] = [:]
        if let list = try? await run(["terminal", "list", "--json"]),
           let lo = try? JSONSerialization.jsonObject(with: list) as? [String: Any],
           let terms = (lo["result"] as? [String: Any])?["terminals"] as? [[String: Any]] {
            for t in terms {
                if let tab = t["tabId"] as? String, let leaf = t["leafId"] as? String, let h = t["handle"] as? String {
                    handles["\(tab):\(leaf)"] = h
                }
            }
        }
        return handles
    }
}
