import AppKit
import SwiftUI

/// Quicksave's design system, layer 1: tokens. Native macOS, sober. Every value the views use lives here,
/// built on system semantic colors so light and dark mode come for free.
enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let s: CGFloat = 4
        static let m: CGFloat = 8
        static let l: CGFloat = 10
    }

    enum Palette {
        static let window = Color(nsColor: .windowBackgroundColor)
        static let surface = Color(nsColor: .controlBackgroundColor)
        static let separator = Color(nsColor: .separatorColor)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let accent = Color.accentColor
        static let warning = Color.orange
        static let highlight = Color.accentColor.opacity(0.16)
        static func tint(_ c: Color) -> Color { c.opacity(0.12) }
        static func pill(_ c: Color) -> Color { c.opacity(0.15) }
    }

    enum Text {
        static let pageTitle = Font.title2.bold()
        static let sectionTitle = Font.title3.bold()
        static let cardTitle = Font.headline
        static let body = Font.callout
        static let meta = Font.caption
        static let label = Font.caption.bold()
        static let micro = Font.caption2.bold()
        static let code = Font.caption.monospaced()
        static let number = Font.callout.monospacedDigit()
    }

    enum Size {
        static let dot: CGFloat = 9
        static let smallDot: CGFloat = 7
        static let columnMin: CGFloat = 220
        static let columnEmptyMin: CGFloat = 110
        static let columnEmptyMax: CGFloat = 130
        static let columnMinHeight: CGFloat = 70
        static let popoverWidth: CGFloat = 520
        static let popoverMaxHeight: CGFloat = 600
        static let stripe: CGFloat = 3
    }
}
