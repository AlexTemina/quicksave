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

    func setSecret(_ name: String, _ value: String?) {
        guard let value, !value.isEmpty else { delete(name); return }
        guard let sealed = try? AES.GCM.seal(Data(value.utf8), using: sealKey).combined else { return }
        put(name, sealed)
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
