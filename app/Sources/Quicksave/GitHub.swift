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
