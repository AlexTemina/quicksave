import AppKit
import SwiftUI

/// Quicksave's design system, layer 2: components. Built only from `Theme` tokens; screens use these, not raw styling.

struct QSCard<Content: View>: View {
    var highlighted = false
    @ViewBuilder let content: Content
    @State private var hovering = false
    /// Lets the card's content show its actions only while the pointer is over it.
    var onHoverChange: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) { content }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(highlighted ? Theme.Palette.highlight : .clear))
                    .shadow(color: hovering ? Theme.Palette.shadowHover : Theme.Palette.shadow, radius: hovering ? 8 : 3, y: hovering ? 3 : 1)
            )
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
            .scaleEffect(hovering ? 1.01 : 1)
            .animation(Theme.Motion.hover, value: hovering)
            .onHover { hovering = $0; onHoverChange($0) }
            .qsClickableCursor()
            .contentShape(Rectangle())
    }
}

/// The one card that matters: the Main Quest. Bigger, a soft accent wash, a hairline accent border.
struct QSHeroCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) { content }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.xl)
                    .fill(Theme.Palette.raised)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.xl).fill(
                            RadialGradient(colors: [Theme.Palette.accent.opacity(0.10), .clear],
                                           center: .topLeading, startRadius: 0, endRadius: 420))
                    )
                    .shadow(color: Theme.Palette.shadow, radius: 10, y: 3)
            )
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl).strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
    }
}

/// One segment per piece, in order, each in its Linear state color.
struct QSProgress: View {
    /// One entry per piece, in order: its state color and whether it is done.
    let segments: [(color: Color, done: Bool)]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                Capsule().fill(seg.done ? seg.color : seg.color.opacity(0.28)).frame(height: Theme.Size.progressHeight)
            }
        }
    }
}

struct QSPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            QSDot(color: color, size: Theme.Size.smallDot)
            Text(text).font(Theme.Text.micro)
        }
        .padding(.horizontal, Theme.Space.s).padding(.vertical, 2)
        .background(Capsule().fill(Theme.Palette.pill(color)))
    }
}

/// A small colored tag with an icon, e.g. "✨ Agent".
struct QSTag: View {
    let text: String
    let icon: String
    let color: Color
    var body: some View {
        Label(text, systemImage: icon)
            .font(Theme.Text.micro)
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Space.s - 2).padding(.vertical, 2)
            .background(Capsule().fill(Theme.Palette.pill(color)))
    }
}

struct QSDot: View {
    let color: Color
    var size: CGFloat = Theme.Size.dot
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

struct QSLabel: View {
    let text: String
    var icon: String?
    var accent = false
    init(_ text: String, icon: String? = nil, accent: Bool = false) { self.text = text; self.icon = icon; self.accent = accent }
    var body: some View {
        HStack(spacing: Theme.Space.xs + 1) {
            if let icon { Image(systemName: icon) }
            Text(text.uppercased())
        }
        .font(Theme.Text.label)
        .foregroundStyle(accent ? Theme.Palette.accent : Theme.Palette.textSecondary)
    }
}

/// Every clickable thing says so on hover: a soft backdrop, a small lift, a pointing-hand cursor; it sinks when pressed.
struct QSHoverStyle: ButtonStyle {
    var padding: CGFloat = 4
    var backdrop = true

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, padding: padding, backdrop: backdrop)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let padding: CGFloat
        let backdrop: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .fill(Color.primary.opacity(backdrop && hovering && enabled ? (configuration.isPressed ? 0.16 : 0.09) : 0))
                )
                .brightness(!backdrop && hovering && enabled ? 0.12 : 0)
                .scaleEffect(configuration.isPressed ? 0.94 : (hovering && enabled ? 1.06 : 1))
                .opacity(enabled ? 1 : 0.35)
                .animation(Theme.Motion.hover, value: hovering)
                .animation(Theme.Motion.hover, value: configuration.isPressed)
                .onHover { hovering = $0 }
                .pointerStyle(enabled ? .link : nil)
        }
    }
}

extension View {
    /// Pointing-hand cursor while over a clickable area that is not a Button (cards). The system owns the
    /// cursor, so it always goes back when the pointer leaves.
    func qsClickableCursor() -> some View { pointerStyle(.link) }
}

struct QSIconButton: View {
    let systemImage: String
    let help: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: systemImage) }
            .buttonStyle(QSHoverStyle())
            .disabled(!enabled)
            .help(help)
    }
}

/// Opens a Linear issue in the browser.
struct LinearButton: View {
    let url: URL?
    var help = "Open in Linear"
    var body: some View {
        QSIconButton(systemImage: "arrow.up.right.square", help: help, enabled: url != nil) {
            if let url { NSWorkspace.shared.open(url) }
        }
    }
}

/// The issue's pull request: its number, opening it on GitHub. Linear's PR colors for its state
/// (open green, draft grey, merged purple, closed brown), and red whenever its CI is failing.
struct PRBadge: View {
    let pr: PullRequest
    let live: GitHub.Status?

    private var state: String { live?.state ?? pr.status ?? "open" }
    private var color: Color {
        if live?.ci == .failing && state == "open" { return Theme.Palette.prFailing }
        switch state {
        case "merged": return Theme.Palette.prMerged
        case "closed": return Theme.Palette.prClosed
        case "draft": return Theme.Palette.prDraft
        default: return Theme.Palette.prOpen
        }
    }
    private var icon: String {
        switch state {
        case "merged": return "arrow.triangle.merge"
        case "closed": return "xmark.circle"
        default: return live?.ci == .failing ? "exclamationmark.triangle.fill" : "arrow.triangle.pull"
        }
    }
    private var help: String {
        var parts = ["PR #\(pr.number)", state]
        if let ci = live?.ci, ci != .none, state == "open" || state == "draft" { parts.append("CI \(ci.rawValue)") }
        return parts.joined(separator: " · ") + ". Open on GitHub"
    }

    var body: some View {
        Button { NSWorkspace.shared.open(pr.url) } label: { QSTag(text: "#\(pr.number)", icon: icon, color: color) }
            .buttonStyle(QSHoverStyle(padding: 0, backdrop: false))
            .help(help)
    }
}

/// Jumps to the issue's worktree in Orca; off when Orca links none.
struct OrcaButton: View {
    let worktree: Orca.Match?
    var onError: (String) -> Void = { _ in }
    var body: some View {
        QSIconButton(systemImage: "terminal",
                     help: worktree.map { "Go to \($0.name) in Orca" + ($0.liveAgentTerminal != nil ? " (agent live)" : "") }
                         ?? "No Orca worktree for this issue",
                     enabled: worktree != nil) {
            guard let worktree else { return }
            Task { do { try await Orca.go(to: worktree) } catch { onError(error.localizedDescription) } }
        }
    }
}

struct QSColumn<Content: View>: View {
    let title: String
    let color: Color
    var count = 0
    var isEmpty = false
    @ViewBuilder let content: Content

    var body: some View {
        if isEmpty { collapsed } else { expanded }
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s - 2) {
                QSDot(color: color)
                Text(title).font(Theme.Text.label)
                Text("\(count)").font(Theme.Text.label).foregroundStyle(Theme.Palette.textTertiary)
            }
            Capsule().fill(color.opacity(0.9)).frame(height: 2)
            content
            Spacer(minLength: 0)
        }
        .frame(minWidth: Theme.Size.columnMin, maxWidth: .infinity, minHeight: Theme.Size.columnMinHeight, alignment: .topLeading)
        .padding(Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.l).fill(Theme.Palette.well))
    }

    /// An empty column is a thin strip: its dot and its name, sideways.
    private var collapsed: some View {
        VStack(spacing: Theme.Space.s) {
            QSDot(color: color.opacity(0.7))
            Text(title).font(Theme.Text.micro).foregroundStyle(Theme.Palette.textTertiary)
                .fixedSize().rotationEffect(.degrees(90)).frame(width: 14, height: 120)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Space.m)
        .frame(width: Theme.Size.columnCollapsed)
        .frame(minHeight: Theme.Size.columnMinHeight + 80)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.l).fill(Theme.Palette.well))
        .help("\(title): empty")
    }
}

struct QSPlaceholder: View {
    let text: String
    var body: some View {
        Text(text).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.l)
                .strokeBorder(Theme.Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}

/// The window's translucent macOS background.
struct QSWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

enum QSDate {
    /// "Today", "Tomorrow", or "Thu 5 Nov" from Linear's yyyy-MM-dd.
    static func friendly(_ ymd: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        guard let d = f.date(from: ymd) else { return ymd }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let out = DateFormatter(); out.locale = Locale(identifier: "en_GB"); out.dateFormat = "EEE d MMM"
        return out.string(from: d)
    }
}

struct QSBanner: View {
    let text: String
    var body: some View {
        HStack {
            Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.Palette.warning).font(Theme.Text.body)
            SettingsLink { Text("Open Settings") }.buttonStyle(QSHoverStyle())
        }
    }
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(h, radix: 16) ?? 0x888888
        self.init(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}
