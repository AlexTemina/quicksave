import Foundation

/// Runs a command and collects what it prints. Output is read while the command runs: a command that prints more than
/// a pipe holds (64 KB) would otherwise wait forever for someone to read it and never finish. On 9-nov that left 26
/// `orca worktree ps` processes hanging and the board never loaded.
enum Shell {
    struct Result { let status: Int32; let out: Data; let err: Data }

    private final class Box: @unchecked Sendable { var out = Data(); var err = Data() }

    static func run(_ binary: String, _ args: [String], environment: [String: String]? = nil) async throws -> Result {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: binary)
            p.arguments = args
            if let environment { p.environment = environment }
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice
            let box = Box()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async { box.out = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
            group.enter()
            DispatchQueue.global().async { box.err = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
            p.terminationHandler = { proc in
                group.notify(queue: .global()) { cont.resume(returning: Result(status: proc.terminationStatus, out: box.out, err: box.err)) }
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}
