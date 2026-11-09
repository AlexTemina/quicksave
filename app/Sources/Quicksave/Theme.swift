import AppKit
import SwiftUI

/// Quicksave's design system, layer 1: tokens. Native macOS, sober. Every value the views use lives here,
/// built on system semantic colors so light and dark mode come for free.
enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 18
        static let xl: CGFloat = 28
    }

    enum Radius {
        static let xs: CGFloat = 4
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 14
        static let xl: CGFloat = 18
    }

    enum Palette {
        /// Cards sit above their column: white in light mode, a lifted grey in dark mode.
        static let surface = Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.19, alpha: 1) : NSColor.white
        })
        static let well = Color.primary.opacity(0.035)
        static let raised = Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.135, alpha: 1) : NSColor(white: 0.975, alpha: 1)
        })
        static let hairline = Color.primary.opacity(0.08)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.primary.opacity(0.35)
        static let accent = Color.accentColor
        static let link = Color(nsColor: .linkColor)
        static let linkHover = Color(nsColor: .linkColor).opacity(0.8)
        static let warning = Color.orange
        static let highlight = Color.accentColor.opacity(0.12)
        static let shadow = Color.black.opacity(0.10)
        static let shadowHover = Color.black.opacity(0.18)
        static func pill(_ c: Color) -> Color { c.opacity(0.16) }
        static let prOpen = Color(hex: "#4cb782")
        static let prDraft = Color(hex: "#95a2b3")
        static let prMerged = Color(hex: "#8b5cf6")
        static let prClosed = Color(hex: "#a87b6a")
        static let prFailing = Color(hex: "#eb5757")
        /// The inbox's four decisions, plus leaving a card for later.
        static let onAccent = Color.white
        static let decisionAccept = prOpen
        static let decisionReject = prFailing
        static let decisionDone = prMerged
        static let decisionCorrect = Color.accentColor
        static let decisionLater = Color.secondary
    }

    enum Text {
        static let pageTitle = Font.system(size: 26, weight: .bold, design: .rounded)
        static let heroTitle = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let cardTitle = Font.system(size: 14, weight: .semibold)
        static let body = Font.system(size: 13)
        static let meta = Font.system(size: 11.5)
        static let label = Font.system(size: 11, weight: .semibold)
        static let micro = Font.system(size: 10.5, weight: .semibold)
        static let code = Font.system(size: 11, weight: .medium, design: .monospaced)
        static let number = Font.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()
    }

    enum Size {
        static let dot: CGFloat = 8
        static let smallDot: CGFloat = 6
        static let columnMin: CGFloat = 230
        static let columnCollapsed: CGFloat = 34
        static let columnMinHeight: CGFloat = 64
        static let popoverWidth: CGFloat = 660
        static let popoverMaxHeight: CGFloat = 780
        static let progressHeight: CGFloat = 6
        static let deckWidth: CGFloat = 640
        static let sheetWidth: CGFloat = 620
        static let sheetMaxHeight: CGFloat = 700
        static let decisionButton: CGFloat = 78
        static let decisionIcon: CGFloat = 20
        static let editorMinHeight: CGFloat = 150
        static let hoverCardWidth: CGFloat = 380
        static let pickerWidth: CGFloat = 540
        static let collectiblesWidth: CGFloat = 300
        static let morningWidth: CGFloat = 720
        static let morningHeight: CGFloat = 800
    }

    /// Game vocabulary as SF Symbols: the day is played like a game.
    enum Icon {
        static let mainQuest = "star.fill"
        static let sideQuests = "map.fill"
        static let due = "hourglass"
        static let qa = "checklist"
        static let questComplete = "trophy.fill"
        static let agentLive = "sparkles"
        static let inbox = "tray.full"
        static let accept = "checkmark"
        static let reject = "xmark"
        static let alreadyDone = "checkmark.seal"
        static let correct = "pencil"
        static let later = "clock"
        static let pullRequest = "arrow.triangle.pull"
        static let morning = "sunrise.fill"
        static let collectibles = "diamond.fill"
    }

    /// The app's crystal as pixel art for the menu bar, one point per pixel. The outline keeps it legible on a light bar.
    enum Crystal {
        static let pixels = [
            ".....K.....",
            "....KWK....",
            "...KWcDK...",
            "..KWcCBDK..",
            ".KWcCCBBVK.",
            ".KccCCBBVK.",
            ".KcCCCBBDK.",
            ".KcCCCBDDK.",
            ".KcCCBBDDK.",
            ".KCCCBBDDK.",
            "..KCCBBDK..",
            "..KCCBBDK..",
            "..KCCBBDK..",
            "...KCBDK...",
            "...KCBDK...",
            "....KBK....",
            "....KBK....",
            ".....K.....",
        ]
        static let colors: [Character: String] = [
            "K": "#16236b", "W": "#f2fdff", "c": "#8fe9ff", "C": "#3fc4f5",
            "B": "#2b7df0", "D": "#1f4fc8", "V": "#a79dff",
        ]
    }

    enum Leading {
        /// Extra space between lines of running text.
        static let body: CGFloat = 3
    }

    enum Motion {
        static let hover = Animation.easeOut(duration: 0.15)
        /// How long the pointer rests on a link before its hover card shows.
        static let hoverCardDelay = Duration.milliseconds(800)
    }
}
