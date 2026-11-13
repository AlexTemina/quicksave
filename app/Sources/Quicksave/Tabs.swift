import AppKit
import Foundation

/// New items per tab: what each tab shows now, minus what he has already seen there. A tab he is looking at, with the
/// window in front, has nothing new. Reviews also count activity on GitHub he has not opened yet.
extension Store {
    static func savedSeen() -> [AppTab: Set<String>] {
        var out: [AppTab: Set<String>] = [:]
        for tab in AppTab.allCases {
            if let ids = Database.shared.value("seen.\(tab.rawValue)", as: [String].self) { out[tab] = Set(ids) }
        }
        return out
    }

    /// The ids of what a tab shows now.
    func items(_ tab: AppTab) -> Set<String> {
        switch tab {
        case .today:
            let pieces = (quest?.pieces ?? []).map(\.id) + sideQuests.map(\.id) + looseWork.map(\.id) + collectibles.map(\.id)
            // Something that moved on a card counts as new each time it moves.
            let news = watchNews.map { "news:\($0.key):\($0.value.at.timeIntervalSince1970)" }
            return Set(pieces + news)
        case .inbox: return Set(pendingCards.map(\.id))
        case .reviews: return Set(reviewRequests.map { "pr:\($0.number)" })
        case .drafts: return Set(drafts.map { "draft:\($0.id)" })
        }
    }

    func newCount(_ tab: AppTab) -> Int {
        guard !(tab == self.tab && NSApp.isActive) else { return 0 }
        // A tab never seen before starts with everything seen, so the first launch does not flood every badge.
        guard let seen = seenItems[tab] else { return 0 }
        let fresh = items(tab).subtracting(seen).count
        if tab == .reviews { return fresh + reviews.values.reduce(0) { $0 + $1.unseenActivity.count } }
        return fresh
    }

    /// He is looking at this tab: everything in it is seen. Kept small: only ids still shown are remembered.
    func markSeen(_ tab: AppTab) {
        let now = items(tab)
        guard seenItems[tab] != now else { return }
        seenItems[tab] = now
        Database.shared.setValue("seen.\(tab.rawValue)", Array(now))
    }

    /// After a refresh: the tab in front is seen, and a tab seen for the first time starts from what it shows.
    func updateSeen() {
        for tab in AppTab.allCases where seenItems[tab] == nil { markSeen(tab) }
        if NSApp.isActive { markSeen(tab) }
    }
}
