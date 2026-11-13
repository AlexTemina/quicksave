import SwiftUI

/// The window: Today (the board) and the Inbox, one tab each.
struct RootView: View {
    @ObservedObject var store: Store

    var body: some View {
        Group {
            switch store.tab {
            case .today: BoardView(store: store)
            case .inbox: InboxView(store: store)
            case .reviews: ReviewsView(store: store)
            case .drafts: DraftsView(store: store)
            }
        }
        .onChange(of: store.tab) { old, new in store.markSeen(old); store.markSeen(new) }
        .sheet(isPresented: $store.morningOpen) { MorningView(store: store) }
        .toolbar {
            ToolbarItem(placement: .principal) {
                QSTabBar(items: [
                    .init(tab: .today, title: "Today", new: store.newCount(.today)),
                    .init(tab: .inbox, title: "Inbox", count: store.pendingCards.count, new: store.newCount(.inbox)),
                    .init(tab: .reviews, title: "Reviews", count: store.reviewRequests.count, new: store.newCount(.reviews)),
                    .init(tab: .drafts, title: "Drafts", count: store.drafts.count, new: store.newCount(.drafts)),
                ], selection: $store.tab)
            }
        }
    }
}
