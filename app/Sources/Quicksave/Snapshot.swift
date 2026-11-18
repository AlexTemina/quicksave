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
        let width = CGFloat(Double(ProcessInfo.processInfo.environment["QUICKSAVE_SNAPSHOT_WIDTH"] ?? "") ?? 944)
        write(AnyView(BoardContent(store: store, wide: width + Theme.Space.xl * 2 >= Theme.Size.wideBoard)), width: width, to: URL(fileURLWithPath: folder).appendingPathComponent("board.png"))
    }

    private static var asksDone = false

    /// "Asked of me" with the board, once GitHub and Linear are read, and again once the agent brings Slack, mail and Notion.
    static func asksIfAsked(_ store: Store, name: String = "asks") {
        guard let folder = ProcessInfo.processInfo.environment["QUICKSAVE_SNAPSHOT"] else { return }
        if name == "asks" { guard !asksDone else { return }; asksDone = true }
        write(AnyView(AsksContent(store: store)), width: 900, to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
        let lines = store.visibleAsks.map { a in
            "\(a.answered ? "answered" : "WAITING") | \(a.origin) | \(a.who) | \(a.place) | \(a.deadline ?? "-") | card \(store.askCards[a.id]?.identifier ?? "none") | \(a.text.prefix(90))"
        }
        try? (lines.joined(separator: "\n") + "\n" + (store.asksError ?? "")).write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
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
            case .expired(let e): view = AnyView(ExpiredCardView(item: e))
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
