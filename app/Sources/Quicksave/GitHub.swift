import Foundation

/// Live PR state and CI, read with the `gh` CLI (Alejandro's logged-in account). Read-only.
enum GitHub {
    enum CI: String { case passing, failing, running, none }
    struct Status { let state: String; let ci: CI }

    static let binary = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }

    static func status(of pr: PullRequest) async -> Status? {
        guard let binary else { return nil }
        let parts = pr.url.path.split(separator: "/")
        guard parts.count >= 4 else { return nil }
        let repo = "\(parts[0])/\(parts[1])"
        guard let data = await run(binary, ["pr", "view", "\(pr.number)", "--repo", repo, "--json", "state,isDraft,statusCheckRollup"]) else { return nil }
        struct PR: Decodable {
            struct Check: Decodable { let conclusion: String?; let status: String?; let state: String? }
            let state: String
            let isDraft: Bool
            let statusCheckRollup: [Check]?
        }
        guard let p = try? JSONDecoder().decode(PR.self, from: data) else { return nil }
        let results = (p.statusCheckRollup ?? []).map { ($0.conclusion ?? $0.state ?? $0.status ?? "").uppercased() }
        let ci: CI
        if results.isEmpty { ci = .none }
        else if results.contains(where: { ["FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE"].contains($0) }) { ci = .failing }
        else if results.contains(where: { ["", "IN_PROGRESS", "QUEUED", "PENDING", "WAITING", "EXPECTED"].contains($0) }) { ci = .running }
        else { ci = .passing }
        let state = p.isDraft && p.state == "OPEN" ? "draft" : p.state.lowercased()
        return Status(state: state, ci: ci)
    }

    /// The second brain, where the auditor opens pull requests for knowledge it wants merged.
    static let vaultRepo = "alan-eu/alextemina-secondbrain"

    /// Open pull requests of the vault, oldest first (a stacked one comes after the one it sits on).
    static func vaultPullRequests() async -> [VaultPullRequest]? {
        guard let binary else { return nil }
        let fields = "number,title,url,body,additions,deletions,createdAt,author,files"
        guard let data = await run(binary, ["pr", "list", "--repo", vaultRepo, "--state", "open", "--json", fields]) else { return nil }
        struct Raw: Decodable {
            struct Author: Decodable { let login: String }
            struct File: Decodable { let path: String }
            let number: Int, title: String, url: String, body: String?, additions: Int, deletions: Int, createdAt: String
            let author: Author?, files: [File]?
        }
        guard let raws = try? JSONDecoder().decode([Raw].self, from: data) else { return nil }
        return raws.compactMap { r in
            guard let url = URL(string: r.url) else { return nil }
            return VaultPullRequest(number: r.number, title: r.title, url: url, body: r.body ?? "", additions: r.additions,
                                    deletions: r.deletions, files: (r.files ?? []).map(\.path),
                                    created: QSDate.parse(r.createdAt), author: r.author?.login ?? "")
        }.sorted { $0.number < $1.number }
    }

    /// Runs a `gh` command that changes something. Returns nil on success, or what `gh` said when it failed.
    static func perform(_ args: [String]) async -> String? {
        guard let binary else { return "The gh command is not installed." }
        return await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: binary)
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.terminationHandler = { proc in
                _ = out.fileHandleForReading.readDataToEndOfFile()
                let said = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                cont.resume(returning: proc.terminationStatus == 0 ? nil : (said.isEmpty ? "gh failed" : said))
            }
            do { try p.run() } catch { cont.resume(returning: error.localizedDescription) }
        }
    }

    private static func run(_ binary: String, _ args: [String]) async -> Data? {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: binary)
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            p.terminationHandler = { proc in
                cont.resume(returning: proc.terminationStatus == 0 ? out.fileHandleForReading.readDataToEndOfFile() : nil)
            }
            do { try p.run() } catch { cont.resume(returning: nil) }
        }
    }
}
