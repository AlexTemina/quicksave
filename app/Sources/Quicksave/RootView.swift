import SwiftUI

/// The window: one tab each for Today (the board), Inbox, Reviews, Drafts and Agents.
struct RootView: View {
    @ObservedObject var store: Store
    @ObservedObject var monitor = AgentMonitor.shared

    var body: some View {
        Group {
            switch store.tab {
            case .today: BoardView(store: store)
            case .oncall: OnCallView(store: store)
            case .asks: AsksView(store: store)
            case .inbox: InboxView(store: store)
            case .reviews: ReviewsView(store: store)
            case .drafts: DraftsView(store: store)
            case .agents: AgentsView(store: store)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !monitor.live.isEmpty { AgentStrip(store: store) }
        }
        .onChange(of: store.tab) { old, new in store.markSeen(old); store.markSeen(new) }
        .sheet(isPresented: $store.morningOpen) { MorningView(store: store) }
        .toolbar {
            ToolbarItem(placement: .principal) {
                QSTabBar(items: [
                    .init(tab: .today, title: "Today", new: store.newCount(.today)),
                ] + (store.showOnCall ? [.init(tab: .oncall, title: "On-call", count: store.onCallCards.filter { $0.column != .done }.count,
                                               new: store.newCount(.oncall))] : []) + [
                    .init(tab: .asks, title: "Asked of me", count: store.waitingAsks.count, new: store.newCount(.asks)),
                    .init(tab: .inbox, title: "Inbox", count: store.pendingCards.count, new: store.newCount(.inbox)),
                    .init(tab: .reviews, title: "Reviews", count: store.reviewRequests.count, new: store.newCount(.reviews)),
                    .init(tab: .drafts, title: "Drafts", count: store.drafts.count, new: store.newCount(.drafts)),
                    .init(tab: .agents, title: "Agents", count: monitor.live.count, new: store.newCount(.agents)),
                ], selection: $store.tab)
            }
        }
    }
}
