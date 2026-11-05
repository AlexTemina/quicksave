import SwiftUI

@main
struct QuicksaveApp: App {
    var body: some Scene {
        Window("Quicksave", id: "main") {
            EmptyDay()
                .frame(minWidth: 480, minHeight: 320)
        }
        .defaultSize(width: 720, height: 480)

        MenuBarExtra("Quicksave", systemImage: "square.and.arrow.down") {
            EmptyDay().padding().frame(width: 280)
        }
        .menuBarExtraStyle(.window)
    }
}

struct EmptyDay: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down").font(.largeTitle)
            Text("Quicksave").font(.title2.bold())
            Text("Nothing yet. The first feature is the Main Quest.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
