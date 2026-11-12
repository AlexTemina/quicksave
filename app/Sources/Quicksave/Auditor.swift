import Foundation

/// The vault's auditor, as the morning shows it: how its last sweep went, source by source, and a way to sweep now.
/// The auditor itself lives in the vault and runs as the Orca automation `auditor-deep`; Quicksave only reads its
/// watermark and asks Orca to start a run.
enum Auditor {
    static let sweepAutomation = "dfd15bdf-7edb-4de7-8152-36ffea86c8e4"
    static let vault = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("vault").path

    struct Source: Identifiable, Equatable {
        let name: String
        let lastSwept: Date?
        let ok: Bool
        let error: String?
        var id: String { name }
    }

    struct Run: Equatable {
        let number: Int
        let status: String
        let started: Date?
        let manual: Bool
        /// What the auditor said when it ended, and when.
        var output: String? = nil
        var ended: Date? = nil
        /// Orca leaves a run "dispatched" while its agent works; one older than three hours is taken as dead.
        var running: Bool {
            if ["queued", "dispatching"].contains(status) { return true }
            guard status == "dispatched", let started else { return false }
            return Date().timeIntervalSince(started) < 3 * 3600
        }
    }

    struct Status: Equatable {
        let sources: [Source]
        let run: Run?
        var failed: [Source] { sources.filter { !$0.ok } }
    }

    static func status() async -> Status {
        async let sources = watermark()
        async let run = lastRun()
        return Status(sources: await sources, run: await run)
    }

    /// The watermark as the vault's `main` holds it, where the auditor commits it. Read only.
    private static func watermark() async -> [Source] {
        guard let r = try? await Shell.run("/usr/bin/git", ["-C", vault, "show", "main:Claude/auditor/state.json"]), r.status == 0,
              let obj = try? JSONSerialization.jsonObject(with: r.out) as? [String: Any],
              let sources = obj["sources"] as? [String: [String: Any]] else { return [] }
        return sources.map { name, s in
            Source(name: name == "github" ? "GitHub" : name.capitalized, lastSwept: (s["last_swept"] as? String).flatMap(QSDate.parse),
                   ok: (s["last_run"] as? String) != "failed", error: s["last_error"] as? String)
        }.sorted { $0.name < $1.name }
    }

    private static func lastRun() async -> Run? {
        guard let data = try? await Orca.automationRuns(sweepAutomation, limit: 1),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runs = (obj["result"] as? [String: Any])?["runs"] as? [[String: Any]], let r = runs.first else { return nil }
        return Run(number: r["runNumber"] as? Int ?? 0, status: r["status"] as? String ?? "",
                   started: (r["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) },
                   manual: (r["trigger"] as? String) == "manual",
                   output: ((r["outputSnapshot"] as? [String: Any])?["content"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                   ended: ((r["outputSnapshot"] as? [String: Any])?["capturedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) })
    }

    static func sweepNow() async throws {
        try await Orca.runAutomation(sweepAutomation)
    }
}

extension Orca {
    static func automationRuns(_ id: String, limit: Int) async throws -> Data {
        try await run(["automations", "runs", "--id", id, "--limit", "\(limit)", "--json"])
    }

    static func runAutomation(_ id: String) async throws {
        _ = try await run(["automations", "run", id, "--json"])
    }
}
