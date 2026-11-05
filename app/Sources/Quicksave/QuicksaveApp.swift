import SwiftUI

@main
struct QuicksaveApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        Window("Quicksave", id: "main") {
            BoardView(store: store)
                .frame(minWidth: 860, minHeight: 420)
                .onAppear { store.start() }
        }
        .defaultSize(width: 1000, height: 560)

        MenuBarExtra {
            MenuView(store: store).onAppear { store.start() }
        } label: {
            if let q = store.quest { Text("💾 \(q.doneCount)/\(q.pieces.count)") } else { Image(systemName: "square.and.arrow.down") }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}
