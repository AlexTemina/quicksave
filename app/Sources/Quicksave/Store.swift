import AppKit
import SwiftUI
import Foundation

@MainActor
final class Store: ObservableObject {
    @Published var quest: MainQuest?
    @Published var stateColors: [String: String] = [:]
    @Published var worktrees: [String: Orca.Match] = [:]
    @Published var error: String?
    @Published var loading = false
    @Published var lastRefresh: Date?

    private var timer: Timer?
    private var observer: NSObjectProtocol?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { await self?.refresh() } }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refresh() }
        }
        Task { await refresh() }
    }

    func refresh() async {
        if loading { return }
        loading = true
        defer { loading = false }
        do {
            guard let key = Database.shared.secret("linearApiKey") else {
                throw QuicksaveError.message("Add your Linear API key in Settings (⌘,).")
            }
            let board = try await Linear.openMainQuests(key: key)
            let open = board.quests
            stateColors = board.stateColors
            quest = open.first.map(MainQuest.init)
            error = open.count > 1 ? "\(open.count) Main Quests are open. Only one should be." : nil
            lastRefresh = Date()
            var found: [String: Orca.Match] = [:]
            for piece in quest?.pieces ?? [] { if let m = await Orca.worktree(for: piece.id) { found[piece.id] = m } }
            worktrees = found
        } catch {
            self.error = error.localizedDescription
        }
    }

    func color(of state: String, fallback: String) -> Color { Color(hex: stateColors[state] ?? fallback) }
}
