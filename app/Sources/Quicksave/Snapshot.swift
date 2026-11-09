import AppKit
import SwiftUI

/// For development: with QUICKSAVE_SNAPSHOT=<folder>, the app draws each inbox card to a PNG in that folder, without
/// going through the screen, so a change can be checked when screen capture is not available.
@MainActor
enum Snapshot {
    private static var done = false
    private static var boardDone = false

    /// The board's side quests and collectibles, once they are loaded.
    static func boardIfAsked(_ store: Store) {
        guard !boardDone, let folder = ProcessInfo.processInfo.environment["QUICKSAVE_SNAPSHOT"] else { return }
        boardDone = true
        let view = HStack(alignment: .top, spacing: Theme.Space.xl) {
            SideQuestsSection(store: store).frame(maxWidth: .infinity)
            CollectiblesSection(store: store).frame(width: Theme.Size.collectiblesWidth)
        }
        write(AnyView(view), width: 960, to: URL(fileURLWithPath: folder).appendingPathComponent("board.png"))
    }

    private static func write(_ view: AnyView, width: CGFloat, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: view.frame(width: width).padding().background(Color.white))
        renderer.scale = 1.5
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    static func inboxIfAsked(_ cards: [InboxCard]) {
        guard !done, let folder = ProcessInfo.processInfo.environment["QUICKSAVE_SNAPSHOT"] else { return }
        done = true
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for card in cards {
            let view: AnyView
            switch card {
            case .triage(let item): view = AnyView(TriageCardView(item: item))
            case .pullRequest(let pr): view = AnyView(PullRequestCardView(pr: pr))
            }
            let renderer = ImageRenderer(content: view.frame(width: Theme.Size.deckWidth).padding().background(Color.white))
            renderer.scale = 1.5
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(card.id).png"))
            }
        }
    }
}
