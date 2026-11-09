import SwiftUI

/// The window: Today (the board) and the Inbox, one tab each.
struct RootView: View {
    @ObservedObject var store: Store

    var body: some View {
        Group {
            switch store.tab {
            case .today: BoardView(store: store)
            case .inbox: InboxView(store: store)
            case .drafts: DraftsView(store: store)
            }
        }
        .sheet(isPresented: $store.morningOpen) { MorningView(store: store) }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $store.tab) {
                    Text("Today").tag(AppTab.today)
                    Text(store.pendingCards.isEmpty ? "Inbox" : "Inbox · \(store.pendingCards.count)").tag(AppTab.inbox)
                    Text(store.drafts.isEmpty ? "Drafts" : "Drafts · \(store.drafts.count)").tag(AppTab.drafts)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 330)
            }
        }
    }
}
