import CryptoKit
import Foundation
import IOKit
import SQLite3

enum QuicksaveError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

/// Local SQLite store in ~/Library/Application Support/Quicksave. Secrets are sealed with AES-GCM under a key
/// derived from this Mac's hardware UUID, so a copy of the file is useless on another machine.
final class Database {
    static let shared = Database()
    private var db: OpaquePointer?
    private let sealKey: SymmetricKey

    private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quicksave", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let path = folder.appendingPathComponent("quicksave.sqlite").path
        if sqlite3_open(path, &db) == SQLITE_OK {
            sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value BLOB NOT NULL)", nil, nil, nil)
            // Decisions about vault pull requests wait here until he presses Apply: a pull request has no state in Linear.
            sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS inbox_pr_decisions (id TEXT PRIMARY KEY, decision TEXT NOT NULL)", nil, nil, nil)
            // Text he posts himself somewhere else. See docs/drafts.md.
            sqlite3_exec(db, """
                CREATE TABLE IF NOT EXISTS drafts (
                  id INTEGER PRIMARY KEY AUTOINCREMENT, place TEXT NOT NULL, link TEXT, body TEXT NOT NULL,
                  source TEXT, created REAL NOT NULL, archived INTEGER NOT NULL DEFAULT 0)
                """, nil, nil, nil)
            // Added later: a line saying what to do with the draft. Fails harmlessly when the column already exists.
            sqlite3_exec(db, "ALTER TABLE drafts ADD COLUMN note TEXT", nil, nil, nil)
            // 1 once the text has been left as a draft in Slack itself.
            sqlite3_exec(db, "ALTER TABLE drafts ADD COLUMN drafted INTEGER NOT NULL DEFAULT 0", nil, nil, nil)
            // The code of the item the draft came from (TEMI-521), so an AI edit can read what is behind it.
            sqlite3_exec(db, "ALTER TABLE drafts ADD COLUMN item TEXT", nil, nil, nil)
            // The session of the agent that wrote it and the folder it ran in, so talking about the draft continues it.
            sqlite3_exec(db, "ALTER TABLE drafts ADD COLUMN session TEXT", nil, nil, nil)
            sqlite3_exec(db, "ALTER TABLE drafts ADD COLUMN session_dir TEXT", nil, nil, nil)
            // The conversation about each draft: his messages, the agent's answers, and every version of the text.
            sqlite3_exec(db, """
                CREATE TABLE IF NOT EXISTS draft_turns (
                  id INTEGER PRIMARY KEY AUTOINCREMENT, draft_id INTEGER NOT NULL, who TEXT NOT NULL, text TEXT NOT NULL,
                  body TEXT, created REAL NOT NULL)
                """, nil, nil, nil)
            // The games used in the standup's simile, so none repeats. See docs/morning.md.
            sqlite3_exec(db, """
                CREATE TABLE IF NOT EXISTS games (
                  id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, score TEXT NOT NULL, game TEXT NOT NULL,
                  simile TEXT NOT NULL, link TEXT)
                """, nil, nil, nil)
        }
        chmod(path, 0o600)
        let uuid = Self.hardwareUUID() ?? "quicksave-no-hardware-uuid"
        sealKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(uuid.utf8)),
                                         salt: Data("com.alextemina.quicksave".utf8),
                                         info: Data("settings-secrets".utf8), outputByteCount: 32)
    }

    func secret(_ name: String) -> String? {
        guard let blob = get(name), let box = try? AES.GCM.SealedBox(combined: blob),
              let plain = try? AES.GCM.open(box, using: sealKey) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    /// A plain value kept in the settings table, as JSON the caller decodes.
    func value<T: Decodable>(_ name: String, as: T.Type) -> T? {
        get(name).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    func setValue<T: Encodable>(_ name: String, _ value: T?) {
        guard let value, let data = try? JSONEncoder().encode(value) else { delete(name); return }
        put(name, data)
    }

    func setSecret(_ name: String, _ value: String?) {
        guard let value, !value.isEmpty else { delete(name); return }
        guard let sealed = try? AES.GCM.seal(Data(value.utf8), using: sealKey).combined else { return }
        put(name, sealed)
    }

    // MARK: Inbox

    func prDecisions() -> [String: String] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        var out: [String: String] = [:]
        guard sqlite3_prepare_v2(db, "SELECT id, decision FROM inbox_pr_decisions", -1, &stmt, nil) == SQLITE_OK else { return out }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let id = sqlite3_column_text(stmt, 0), let d = sqlite3_column_text(stmt, 1) { out[String(cString: id)] = String(cString: d) }
        }
        return out
    }

    /// Remembers a decision about a pull request, or forgets it when `decision` is nil.
    func setPRDecision(_ id: String, _ decision: String?) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        if let decision {
            guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO inbox_pr_decisions (id, decision) VALUES (?, ?)", -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, id, -1, Self.transient)
            sqlite3_bind_text(stmt, 2, decision, -1, Self.transient)
        } else {
            guard sqlite3_prepare_v2(db, "DELETE FROM inbox_pr_decisions WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, id, -1, Self.transient)
        }
        sqlite3_step(stmt)
    }

    func addDraft(place: String, note: String, link: String?, body: String, source: String?, item: String?,
                  session: String? = nil, sessionDir: String? = nil) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "INSERT INTO drafts (place, link, body, source, created, note, item, session, session_dir) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", -1, &stmt, nil) == SQLITE_OK else { return }
        if let session { sqlite3_bind_text(stmt, 8, session, -1, Self.transient) } else { sqlite3_bind_null(stmt, 8) }
        if let sessionDir { sqlite3_bind_text(stmt, 9, sessionDir, -1, Self.transient) } else { sqlite3_bind_null(stmt, 9) }
        if let item { sqlite3_bind_text(stmt, 7, item, -1, Self.transient) } else { sqlite3_bind_null(stmt, 7) }
        sqlite3_bind_text(stmt, 1, place, -1, Self.transient)
        if let link { sqlite3_bind_text(stmt, 2, link, -1, Self.transient) } else { sqlite3_bind_null(stmt, 2) }
        sqlite3_bind_text(stmt, 3, body, -1, Self.transient)
        if let source { sqlite3_bind_text(stmt, 4, source, -1, Self.transient) } else { sqlite3_bind_null(stmt, 4) }
        sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 6, note, -1, Self.transient)
        sqlite3_step(stmt)
    }

    /// Open drafts, or the archived ones, newest first.
    func drafts(archived: Bool) -> [DraftItem] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        var out: [DraftItem] = []
        let sql = "SELECT id, place, link, body, source, created, note, drafted, item, session, session_dir FROM drafts WHERE archived = ? ORDER BY created DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return out }
        sqlite3_bind_int(stmt, 1, archived ? 1 : 0)
        func text(_ i: Int32) -> String? { sqlite3_column_text(stmt, i).map { String(cString: $0) } }
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(DraftItem(id: sqlite3_column_int64(stmt, 0), place: text(1) ?? "Other", note: text(6) ?? "",
                                 link: text(2).flatMap(URL.init), body: text(3) ?? "", source: text(4) ?? "",
                                 created: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
                                 drafted: sqlite3_column_int(stmt, 7) == 1, item: text(8) ?? "",
                                 session: text(9), sessionDir: text(10)))
        }
        return out
    }

    /// Replaces a draft's text. A text edited after it was left in Slack is no longer the one that is there,
    /// so it counts as not yet drafted there.
    func updateDraftBody(_ id: Int64, _ body: String) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "UPDATE drafts SET body = ?, drafted = 0 WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, body, -1, Self.transient)
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    /// The text now sits as a draft in Slack. The link, when Slack gave one, points at the channel.
    func markDrafted(_ id: Int64, link: String?) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "UPDATE drafts SET drafted = 1, link = COALESCE(?, link) WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        if let link { sqlite3_bind_text(stmt, 1, link, -1, Self.transient) } else { sqlite3_bind_null(stmt, 1) }
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    func setDraftSession(_ id: Int64, session: String, dir: String) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "UPDATE drafts SET session = ?, session_dir = ? WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, session, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, dir, -1, Self.transient)
        sqlite3_bind_int64(stmt, 3, id)
        sqlite3_step(stmt)
    }

    func addDraftTurn(_ draft: Int64, who: DraftTurn.Who, text: String, body: String?) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "INSERT INTO draft_turns (draft_id, who, text, body, created) VALUES (?, ?, ?, ?, ?)", -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_int64(stmt, 1, draft)
        sqlite3_bind_text(stmt, 2, who.rawValue, -1, Self.transient)
        sqlite3_bind_text(stmt, 3, text, -1, Self.transient)
        if let body { sqlite3_bind_text(stmt, 4, body, -1, Self.transient) } else { sqlite3_bind_null(stmt, 4) }
        sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    /// Every turn of every draft's conversation, oldest first, by draft.
    func draftTurns() -> [Int64: [DraftTurn]] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        var out: [Int64: [DraftTurn]] = [:]
        guard sqlite3_prepare_v2(db, "SELECT id, draft_id, who, text, body, created FROM draft_turns ORDER BY id", -1, &stmt, nil) == SQLITE_OK else { return out }
        func text(_ i: Int32) -> String? { sqlite3_column_text(stmt, i).map { String(cString: $0) } }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let draft = sqlite3_column_int64(stmt, 1)
            out[draft, default: []].append(DraftTurn(id: sqlite3_column_int64(stmt, 0), who: DraftTurn.Who(rawValue: text(2) ?? "") ?? .me,
                                                     text: text(3) ?? "", body: text(4),
                                                     created: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))))
        }
        return out
    }

    func setDraftsArchived(_ ids: [Int64], _ archived: Bool) {
        for id in ids {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "UPDATE drafts SET archived = ? WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { continue }
            sqlite3_bind_int(stmt, 1, archived ? 1 : 0)
            sqlite3_bind_int64(stmt, 2, id)
            sqlite3_step(stmt)
        }
    }

    // MARK: Games

    /// Every game used in a standup, newest first.
    func games() -> [GameEntry] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        var out: [GameEntry] = []
        guard sqlite3_prepare_v2(db, "SELECT id, date, score, game, simile, link FROM games ORDER BY date DESC, id DESC", -1, &stmt, nil) == SQLITE_OK else { return out }
        func text(_ i: Int32) -> String? { sqlite3_column_text(stmt, i).map { String(cString: $0) } }
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(GameEntry(id: sqlite3_column_int64(stmt, 0), date: text(1) ?? "", score: text(2) ?? "",
                                 game: text(3) ?? "", simile: text(4) ?? "", link: text(5).flatMap(URL.init)))
        }
        return out
    }

    func addGame(date: String, score: String, game: String, simile: String, link: String?) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "INSERT INTO games (date, score, game, simile, link) VALUES (?, ?, ?, ?, ?)", -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, date, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, score, -1, Self.transient)
        sqlite3_bind_text(stmt, 3, game, -1, Self.transient)
        sqlite3_bind_text(stmt, 4, simile, -1, Self.transient)
        if let link { sqlite3_bind_text(stmt, 5, link, -1, Self.transient) } else { sqlite3_bind_null(stmt, 5) }
        sqlite3_step(stmt)
    }

    /// Brings in the vault's log of games once, when the table is still empty. From then on the log lives here.
    func importGamesFromVaultIfEmpty() {
        guard games().isEmpty else { return }
        let path = NSHomeDirectory() + "/vault/Personal/Standup Game Similes.md"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        for line in text.components(separatedBy: "\n") where line.hasPrefix("| 20") {
            let cols = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cols.count >= 5 else { continue }
            let game = cols[3].replacingOccurrences(of: "**", with: "")
            var link: String?
            if cols.count > 5, let r = cols[5].range(of: #"\]\((https?://[^)]+)\)"#, options: .regularExpression) {
                link = String(cols[5][r].dropFirst(2).dropLast())
            }
            addGame(date: cols[1], score: cols[2], game: game, simile: cols[4], link: link)
        }
    }

    private func get(_ name: String) -> Data? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT value FROM settings WHERE key = ?", -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, name, -1, Self.transient)
        guard sqlite3_step(stmt) == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 0) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))
    }

    private func put(_ name: String, _ value: Data) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, name, -1, Self.transient)
        _ = value.withUnsafeBytes { sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(value.count), Self.transient) }
        sqlite3_step(stmt)
    }

    private func delete(_ name: String) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "DELETE FROM settings WHERE key = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, name, -1, Self.transient)
        sqlite3_step(stmt)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }
}
