import AppKit
import Foundation

enum AgentRunState: String {
    case queued, running, done, needsYou = "needs_you", failed, cancelled
    var isLive: Bool { self == .queued || self == .running }
}

/// One background agent run, as kept in the local database.
struct AgentRunRecord: Identifiable, Equatable {
    let id: Int64
    let job: String
    let directory: String
    let model: String
    var state: AgentRunState
    let queued: Date
    var started: Date?
    var ended: Date?
    var cost: Double?
    var turns: Int?
    var denials: [String] = []
    var result: String?
    var error: String?
    var sessionId: String?
    /// The file with everything the agent printed, one JSON event per line. Nil once it is older than the retention.
    var transcript: String?

    var duration: TimeInterval? { started.map { (ended ?? Date()).timeIntervalSince($0) } }
}

/// Every background agent Quicksave starts goes through here: it is recorded, waits its turn in its folder, can be
/// cancelled, and stays in the history. See docs/background-agents.md.
@MainActor
final class AgentMonitor: ObservableObject {
    static let shared = AgentMonitor()

    /// Full transcripts are deleted after this long. The row stays.
    static let keepTranscripts: TimeInterval = 30 * 24 * 3600

    @Published private(set) var runs: [AgentRunRecord] = []
    /// What each running agent is doing right now, in a few words.
    @Published private(set) var steps: [Int64: String] = [:]
    /// The run shown in the Agents tab.
    @Published var selected: Int64?

    private var processes: [Int64: Process] = [:]
    private var cancelled: Set<Int64> = []
    private var busyFolders: Set<String> = []
    private var waiting: [String: [(id: Int64, cont: CheckedContinuation<Void, Error>)]] = [:]

    static let transcriptFolder: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quicksave/runs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }()

    private init() {
        // Runs left queued or running belong to a Quicksave that quit before they ended.
        for var r in Database.shared.runs() where r.state.isLive {
            r.state = .failed
            r.ended = r.ended ?? r.started ?? r.queued
            r.error = "Quicksave quit while this run was \(r.started == nil ? "queued" : "running")."
            Database.shared.updateRun(r)
        }
        for path in Database.shared.dropTranscripts(before: Date().addingTimeInterval(-Self.keepTranscripts)) {
            try? FileManager.default.removeItem(atPath: path)
        }
        runs = Database.shared.runs()
    }

    var live: [AgentRunRecord] { runs.filter(\.state.isLive) }

    // MARK: Lifecycle, called by Agents.run

    func enqueue(_ job: AgentJob) -> AgentRunRecord {
        let now = Date()
        let id = Database.shared.insertRun(job: job.name, directory: job.directory, model: job.model, queued: now)
        var r = AgentRunRecord(id: id, job: job.name, directory: job.directory, model: job.model, state: .queued, queued: now)
        r.transcript = Self.transcriptFolder.appendingPathComponent("\(id).jsonl").path
        Database.shared.updateRun(r)
        runs.insert(r, at: 0)
        return r
    }

    /// Two runs in the same folder would collide, so they take turns. Runs in the temporary folder touch no files
    /// and never wait.
    nonisolated static func lockKey(_ directory: String) -> String? {
        let dir = URL(fileURLWithPath: directory).standardizedFileURL.resolvingSymlinksInPath().path
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.resolvingSymlinksInPath().path
        return dir.hasPrefix(tmp) ? nil : dir
    }

    func waitTurn(_ id: Int64, key: String?) async throws {
        guard let key else { return }
        if !busyFolders.contains(key) { busyFolders.insert(key); return }
        try await withCheckedThrowingContinuation { cont in waiting[key, default: []].append((id, cont)) }
    }

    func started(_ id: Int64, process: Process) {
        guard runs.first(where: { $0.id == id })?.state == .queued else { return }
        processes[id] = process
        update(id) { $0.state = .running; $0.started = Date() }
        // Cancelled in the instant between its turn coming and the process starting.
        if cancelled.contains(id) { process.terminate() }
    }

    func step(_ id: Int64, _ text: String) {
        if steps[id] != text { steps[id] = text }
    }

    func wasCancelled(_ id: Int64) -> Bool { cancelled.contains(id) }

    func finish(_ id: Int64, key: String?, outcome: Result<AgentRun, Error>, needsYou: Bool) {
        processes[id] = nil
        steps[id] = nil
        let wasCancelled = cancelled.remove(id) != nil
        update(id) { r in
            r.ended = Date()
            switch outcome {
            case .success(let run):
                r.state = needsYou ? .needsYou : .done
                r.cost = run.cost
                r.turns = run.turns
                r.denials = run.denials
                r.result = run.resultJSON
                r.sessionId = run.sessionId
            case .failure(let error):
                r.state = wasCancelled ? .cancelled : .failed
                r.error = wasCancelled ? "Cancelled from Quicksave." : error.localizedDescription
            }
        }
        release(key)
    }

    /// Stops a run: one still waiting never starts, one running is told to stop.
    func cancel(_ id: Int64) {
        guard let r = runs.first(where: { $0.id == id }), r.state.isLive else { return }
        if let key = Self.lockKey(r.directory), let i = waiting[key]?.firstIndex(where: { $0.id == id }) {
            let cont = waiting[key]!.remove(at: i).cont
            update(id) { $0.state = .cancelled; $0.ended = Date(); $0.error = "Cancelled from Quicksave before it started." }
            cont.resume(throwing: QuicksaveError.message("Cancelled from Quicksave."))
            return
        }
        cancelled.insert(id)
        processes[id]?.terminate()
    }

    private func release(_ key: String?) {
        guard let key else { return }
        if var queue = waiting[key], !queue.isEmpty {
            let next = queue.removeFirst()
            waiting[key] = queue
            next.cont.resume()
        } else {
            busyFolders.remove(key)
        }
    }

    private func update(_ id: Int64, _ change: (inout AgentRunRecord) -> Void) {
        guard let i = runs.firstIndex(where: { $0.id == id }) else { return }
        change(&runs[i])
        Database.shared.updateRun(runs[i])
    }

    // MARK: Reading a transcript

    struct Entry: Identifiable {
        enum Kind { case said, action, output, failedOutput }
        let id: Int
        let kind: Kind
        let title: String
        let detail: String
    }

    /// What the agent did, read from its transcript: what it said, each action and what came back.
    nonisolated static func entries(_ path: String) -> [Entry] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var out: [Entry] = []
        func add(_ kind: Entry.Kind, _ title: String, _ detail: String) { out.append(Entry(id: out.count, kind: kind, title: title, detail: detail)) }
        for line in text.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] else { continue }
            for part in content {
                switch part["type"] as? String {
                case "text":
                    let t = (part["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { add(.said, "Said", t) }
                case "tool_use":
                    let name = part["name"] as? String ?? "tool"
                    let input = part["input"] as? [String: Any] ?? [:]
                    add(.action, Agents.describe(tool: name, input: input), name + ": " + Self.summary(input))
                case "tool_result":
                    var body = ""
                    if let s = part["content"] as? String { body = s }
                    else if let parts = part["content"] as? [[String: Any]] { body = parts.compactMap { $0["text"] as? String }.joined(separator: "\n") }
                    let error = part["is_error"] as? Bool == true
                    add(error ? .failedOutput : .output, error ? "Refused or failed" : "Got back", Self.clip(body, 1500))
                default: continue
                }
            }
        }
        return out
    }

    private nonisolated static func summary(_ input: [String: Any]) -> String {
        for key in ["command", "file_path", "pattern", "query", "url", "path"] {
            if let v = input[key] as? String { return clip(v, 600) }
        }
        guard JSONSerialization.isValidJSONObject(input),
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]) else { return "" }
        return clip(String(data: data, encoding: .utf8) ?? "", 600)
    }

    private nonisolated static func clip(_ s: String, _ n: Int) -> String { s.count > n ? String(s.prefix(n)) + "…" : s }
}
