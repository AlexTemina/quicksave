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
        guard let env = try? JSONDecoder().decode(Env.self, from: data) else { return nil }
        let matches = env.result.matches.filter { $0.workspace.archived != true }
        let pick = matches.first { $0.agents?.contains { $0.liveness == "live" } == true } ?? matches.first
        guard let pick else { return nil }
        return Match(worktreeId: pick.workspace.id, name: pick.workspace.name,
                     liveAgentTerminal: pick.agents?.first { $0.liveness == "live" }?.terminal)
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
    static func linearWrite(_ args: [String]) async throws {
        let data = try await run(["linear"] + args + ["--json"])
        struct Env: Decodable { struct E: Decodable { let message: String? }; let ok: Bool?; let error: E? }
        if let env = try? JSONDecoder().decode(Env.self, from: data), env.ok == false {
            throw QuicksaveError.message(env.error?.message ?? "Linear refused the change")
        }
    }

    private static func run(_ args: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: binary)
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.terminationHandler = { proc in
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let problem = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if proc.terminationStatus == 0 { cont.resume(returning: data) }
                else {
                    var message = problem.isEmpty ? (String(data: data, encoding: .utf8) ?? "") : problem
                    if message.count > 300 { message = String(message.prefix(300)) + "…" }
                    cont.resume(throwing: QuicksaveError.message(message.isEmpty ? "orca \(args.prefix(2).joined(separator: " ")) failed" : message))
                }
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}
