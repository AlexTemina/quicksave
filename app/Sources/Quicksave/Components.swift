import AppKit
import SwiftUI
import WebKit

/// Quicksave's design system, layer 2: components. Built only from `Theme` tokens; screens use these, not raw styling.

/// The crystal as a full-color image, sharp on Retina and kept in color by the menu bar.
enum QSCrystalMark {
    static let image: NSImage = {
        let rows = Theme.Crystal.pixels
        let height = rows.count
        let width = rows[0].count
        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            for (y, row) in rows.enumerated() {
                for (x, pixel) in row.enumerated() {
                    guard let hex = Theme.Crystal.colors[pixel] else { continue }
                    NSColor(Color(hex: hex)).setFill()
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }()
}

struct QSCard<Content: View>: View {
    var highlighted = false
    /// A color that paints the whole card, to read its state at a glance (the agent's, on quest cards).
    var tint: Color? = nil
    /// The tint breathes slowly, for something that is happening right now.
    var pulsing = false
    /// The tint blinks fast, for something that is stuck until he acts.
    var blinking = false
    /// A dashed edge and a lighter fill: something on the board that is not part of the plan.
    var dashed = false
    @ViewBuilder let content: Content
    @State private var hovering = false
    /// Lets the card's content show its actions only while the pointer is over it.
    var onHoverChange: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) { content }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m).fill(dashed ? Theme.Palette.well : Theme.Palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(highlighted ? Theme.Palette.highlight : .clear))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).fill((tint ?? .clear).opacity(pulsing || blinking ? Theme.Opacity.breathLow : Theme.Opacity.tint)))
                    // The breath is its own view, there only while pulsing: when the state changes it is gone at once,
                    // instead of an endless animation carrying the old color on.
                    .overlay {
                        if blinking, let tint { QSBreath(color: tint, radius: Theme.Radius.m, motion: Theme.Motion.blink).id("blink") }
                        else if pulsing, let tint { QSBreath(color: tint, radius: Theme.Radius.m).id(tint) }
                    }
                    .shadow(color: hovering ? Theme.Palette.shadowHover : Theme.Palette.shadow, radius: hovering ? 8 : 3, y: hovering ? 3 : 1)
            )
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m)
                .strokeBorder(dashed ? Theme.Palette.textTertiary : Theme.Palette.hairline,
                              style: StrokeStyle(lineWidth: dashed ? 1.2 : 0.5, dash: dashed ? [5, 4] : [])))
            .scaleEffect(hovering ? 1.01 : 1)
            .animation(Theme.Motion.hover, value: hovering)
            .onHover { hovering = $0; onHoverChange($0) }
            .qsClickableCursor()
            .contentShape(Rectangle())
    }
}

/// A color that slowly brightens and fades over a card, for something happening right now.
struct QSBreath: View {
    let color: Color
    let radius: CGFloat
    var motion: Animation = Theme.Motion.breath
    @State private var on = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(color)
            .opacity(on ? Theme.Opacity.breathHigh - Theme.Opacity.breathLow : 0)
            .allowsHitTesting(false)
            .onAppear { withAnimation(motion) { on = true } }
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

/// A card of the inbox's deck. It takes the height its content needs; when the window is too short it keeps its
/// frame whole, with its rounded corners, and only its content scrolls.
struct QSDeckCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            shell { inner }
            shell { ScrollView { inner }.scrollBounceBehavior(.basedOnSize) }
        }
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) { content }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shell<Inner: View>(@ViewBuilder _ inner: () -> Inner) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.xl)
        return inner()
            .clipShape(shape)
            .background(
                shape.fill(Theme.Palette.raised)
                    .overlay(shape.fill(RadialGradient(colors: [Theme.Palette.accent.opacity(0.10), .clear],
                                                       center: .topLeading, startRadius: 0, endRadius: 420)))
                    .shadow(color: Theme.Palette.shadow, radius: 10, y: 3)
            )
            .overlay(shape.strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
    }
}

/// Lays its items out in a row and wraps to the next line when they do not fit, like words in a sentence.
/// Each item keeps its own size: nothing is squeezed.
struct QSFlow: Layout {
    var spacing: CGFloat = Theme.Space.s
    var lineSpacing: CGFloat = Theme.Space.xs

    private func lines(_ subviews: Subviews, width: CGFloat) -> [[(LayoutSubview, CGSize)]] {
        var out: [[(LayoutSubview, CGSize)]] = [[]]
        var x: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { out.append([]); x = 0 }
            out[out.count - 1].append((view, size))
            x += size.width + spacing
        }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Asked for its ideal width, it answers with its widest item, so a card never claims the whole row of badges.
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let rows = lines(subviews, width: width + 0.5)
        var widest: CGFloat = 0
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            var rowWidth: CGFloat = 0
            var rowHeight: CGFloat = 0
            for (_, size) in row { rowWidth += size.width; rowHeight = max(rowHeight, size.height) }
            rowWidth += spacing * CGFloat(max(0, row.count - 1))
            widest = max(widest, rowWidth)
            height += rowHeight + (i > 0 ? lineSpacing : 0)
        }
        return CGSize(width: min(widest, width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        // The same width the size was measured with, plus a hair: rounding must never wrap one more line than measured.
        for row in lines(subviews, width: (proposal.width ?? bounds.width) + 0.5) {
            let height = row.map(\.1.height).max() ?? 0
            var x = bounds.minX
            for (view, size) in row {
                view.place(at: CGPoint(x: x, y: y + (height - size.height) / 2), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += height + lineSpacing
        }
    }
}

/// A game progress bar: one segment per thing to do. A done segment fills with a glossy gradient and pops up; the
/// bar springs when it moves and glows once every segment is done. The day should feel good to fill.
struct QSProgress: View {
    /// One entry per thing, in order: its color and whether it is done.
    let segments: [(color: Color, done: Bool)]
    var height: CGFloat = Theme.Size.progressHeight

    var body: some View {
        let complete = !segments.isEmpty && segments.allSatisfy(\.done)
        HStack(spacing: max(2, height * 0.3)) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                Capsule()
                    .fill(seg.done ? AnyShapeStyle(LinearGradient(colors: [seg.color.opacity(0.75), seg.color], startPoint: .top, endPoint: .bottom))
                                   : AnyShapeStyle(seg.color.opacity(0.2)))
                    .frame(height: height)
                    .overlay(alignment: .top) {
                        if seg.done {
                            Capsule().fill(Color.white.opacity(0.4)).frame(height: max(1, height * 0.3))
                                .padding(.horizontal, height * 0.3).padding(.top, max(1, height * 0.12))
                        }
                    }
                    .scaleEffect(y: seg.done ? 1 : 0.75)
            }
        }
        .shadow(color: complete ? (segments.last?.color ?? Theme.Palette.questMain).opacity(0.6) : .clear, radius: height * 0.7)
        .animation(Theme.Motion.fill, value: segments.map(\.done))
    }
}

/// The day as one bar: the Main Quest's pieces and today's side quests, each in its own color.
struct QSDayProgress: View {
    let mainDone: Int
    let mainTotal: Int
    let sideDone: Int
    let sideTotal: Int

    var body: some View {
        let done = mainDone + sideDone, total = mainTotal + sideTotal
        HStack(spacing: Theme.Space.m) {
            QSLabel("Day", icon: "flag.checkered")
            QSProgress(segments: (0..<mainTotal).map { (Theme.Palette.questMain, $0 < mainDone) }
                                 + (0..<sideTotal).map { (Theme.Palette.questSide, $0 < sideDone) },
                       height: Theme.Size.dayBarHeight)
            if total > 0 && done == total {
                Label("Day cleared", systemImage: Theme.Icon.questComplete).font(Theme.Text.number).foregroundStyle(Theme.Palette.questMain)
            } else {
                Text("\(done)/\(total)").font(Theme.Text.number).foregroundStyle(Theme.Palette.textSecondary)
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

/// Every link of the app goes through this button: it opens the URL and, resting on it, shows its hover card.
/// A link with a card needs no tooltip, the card says more.
struct QSLinkButton<Label: View>: View {
    let url: URL?
    var help = "Open"
    var padding: CGFloat = 4
    var backdrop = true
    @ViewBuilder let label: Label

    var body: some View {
        Button { if let url { NSWorkspace.shared.open(url) } } label: { label }
            .buttonStyle(QSHoverStyle(padding: padding, backdrop: backdrop))
            .disabled(url == nil)
            .help(url.flatMap(LinkTarget.init) == nil ? help : "")
            .linkPreview(url)
    }
}

/// The small "open" arrow next to a code or a title.
struct QSOpenLinkButton: View {
    let url: URL?
    var help = "Open"
    var padding: CGFloat = 4
    var body: some View {
        QSLinkButton(url: url, help: help, padding: padding) { Image(systemName: "arrow.up.right.square") }
    }
}

/// The issue's pull request: its number, opening it on GitHub. Linear's PR colors for its state
/// (open green, draft grey, merged purple, closed brown), and red whenever its CI is failing.
struct PRBadge: View {
    let pr: PullRequest
    let live: GitHub.Status?

    var body: some View {
        let look = PRLook(pr: pr, live: live)
        QSLinkButton(url: pr.url, padding: 0, backdrop: false) { QSTag(text: "#\(pr.number)", icon: look.icon, color: look.color) }
    }
}

/// How a pull request shows: its color, its icon, and how much it asks for attention (failing first, closed last).
struct PRLook {
    let color: Color
    let icon: String
    let urgency: Int

    init(pr: PullRequest, live: GitHub.Status?) {
        let state = live?.state ?? pr.status ?? "open"
        let failing = live?.ci == .failing && state == "open"
        switch state {
        case "merged": (color, icon, urgency) = (Theme.Palette.prMerged, "arrow.triangle.merge", 1)
        case "closed": (color, icon, urgency) = (Theme.Palette.prClosed, "xmark.circle", 0)
        case "draft": (color, icon, urgency) = (Theme.Palette.prDraft, "arrow.triangle.pull", 2)
        default:
            (color, icon, urgency) = failing
                ? (Theme.Palette.prFailing, "exclamationmark.triangle.fill", 4)
                : (Theme.Palette.prOpen, "arrow.triangle.pull", 3)
        }
    }
}

/// An issue's pull requests on a card. One shows as its badge; several fold into one tag ("3 PRs") in the color of the
/// one that needs him most, and hovering it lists them all, each one clickable.
struct PRStack: View {
    let prs: [PullRequest]
    let live: [Int: GitHub.Status]
    @State private var hoveringTag = false
    @State private var hoveringList = false
    @State private var shown = false
    @State private var timer: Task<Void, Never>?

    var body: some View {
        if prs.count <= 1 {
            ForEach(prs, id: \.number) { PRBadge(pr: $0, live: live[$0.number]) }
        } else {
            let top = prs.map { PRLook(pr: $0, live: live[$0.number]) }.max { $0.urgency < $1.urgency }!
            QSTag(text: "\(prs.count) PRs", icon: top.icon, color: top.color)
                .contentShape(Capsule())
                .onHover { hoveringTag = $0; schedule() }
                .popover(isPresented: $shown, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        ForEach(prs, id: \.number) { pr in
                            HStack(spacing: Theme.Space.s) {
                                PRBadge(pr: pr, live: live[pr.number]).fixedSize()
                                if let title = pr.title, !title.isEmpty {
                                    Text(title).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(Theme.Space.m)
                    .frame(maxWidth: Theme.Size.hoverCardWidth, alignment: .leading)
                    .onHover { hoveringList = $0; schedule() }
                }
        }
    }

    /// Opens shortly after the pointer rests on the tag, and closes once it has left both the tag and the list.
    private func schedule() {
        timer?.cancel()
        let over = hoveringTag || hoveringList
        if over == shown { return }
        timer = Task { @MainActor in
            try? await Task.sleep(for: over ? .milliseconds(250) : .milliseconds(350))
            if !Task.isCancelled { shown = hoveringTag || hoveringList }
        }
    }
}

extension Orca.AgentState {
    /// The color a quest card takes for its agent: yellow working, orange its turn ended, purple stopped on a
    /// question or a permission, grey idle, red error.
    var tint: Color {
        switch state {
        case "working": return Theme.Palette.agentWorking
        case "blocked": return Theme.Palette.agentAsking
        case "done", "monitoring": return Theme.Palette.agentWaiting
        case "error": return Theme.Palette.prFailing
        default: return Theme.Palette.agentIdle
        }
    }
}

/// What the issue's agent is doing, as a tag: Working pulses, Asks you blinks while it waits on his answer, Your turn says it finished.
/// The actions of a card, floating over its top corner while the pointer is over the card, so they take no room
/// from what the card says.
struct QSHoverActions<Content: View>: View {
    let visible: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: Theme.Space.s) { content }
            .padding(.horizontal, Theme.Space.xs)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.surface))
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .animation(Theme.Motion.hover, value: visible)
            .offset(y: -2)
    }
}

/// Closes an agent's tab in Orca. Shown only for an agent with an open terminal. A working agent asks first, since
/// what it is doing is lost; one that waits or is idle closes at once.
struct CloseAgentButton: View {
    let agent: Orca.AgentState
    @ObservedObject var store: Store
    @State private var confirming = false

    var body: some View {
        if let handle = agent.terminal {
            if store.closingAgents.contains(handle) {
                ProgressView().controlSize(.small).help("Closing the agent in Orca…")
            } else {
                QSIconButton(systemImage: "xmark.circle",
                             help: "Close this agent's tab in Orca. The worktree, its files and Linear do not change.") {
                    if agent.state == "working" { confirming = true } else { Task { await store.closeAgent(agent) } }
                }
                .confirmationDialog("Close the agent while it works?", isPresented: $confirming) {
                    Button("Close it", role: .destructive) { Task { await store.closeAgent(agent) } }
                } message: {
                    Text("\(agent.name.isEmpty ? "The agent" : agent.name) is working. Closing its tab ends its session and what it is doing is lost. The worktree and its files stay.")
                }
            }
        }
    }
}

/// What an agent is doing and the last thing it said, in full, with when it last moved and where it runs.
struct AgentReplyBox: View {
    let agent: Orca.AgentState
    var showPlace = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                QSLabel("Agent", icon: Theme.Icon.agentLive)
                QSAgentTag(agent: agent)
                if agent.updatedAt > 0 {
                    Text(QSDate.ago(Date(timeIntervalSince1970: agent.updatedAt / 1000)))
                        .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary)
                }
                if showPlace {
                    Text(agent.place).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                }
            }
            if agent.lastMessage.isEmpty {
                Text("It has not said anything yet.").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary)
            } else {
                MarkdownBlock(agent.lastMessage).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.well))
    }
}

struct QSAgentTag: View {
    let agent: Orca.AgentState

    private var look: (text: String, icon: String, color: Color)? {
        switch agent.state {
        case "working": return ("Working", Theme.Icon.agentLive, Theme.Palette.agentWorking)
        case "blocked": return ("Asks you", "questionmark.bubble.fill", Theme.Palette.agentAsking)
        case "done": return ("Your turn", "checkmark.bubble.fill", Theme.Palette.agentWaiting)
        case "monitoring": return ("Your turn, watching", "eye.fill", Theme.Palette.agentWaiting)
        case "error": return ("Error", "exclamationmark.octagon.fill", Theme.Palette.prFailing)
        default: return ("Idle", "moon.zzz.fill", Theme.Palette.agentIdle)
        }
    }

    var body: some View {
        if let look {
            Label(look.text, systemImage: look.icon)
                .font(Theme.Text.micro)
                .foregroundStyle(look.color)
                .symbolEffect(.pulse, isActive: agent.state == "working" || agent.state == "blocked")
                .padding(.horizontal, Theme.Space.s - 2).padding(.vertical, 2)
                .background(Capsule().fill(Theme.Palette.pill(look.color)))
                .fixedSize()
                .help(agent.lastMessage.isEmpty ? agent.name : String(agent.lastMessage.prefix(400)))
        }
    }
}

/// Jumps to the issue's agent or worktree in Orca. With neither, it starts one (`onStart`); while that runs it spins.
struct OrcaButton: View {
    let worktree: Orca.Match?
    var starting = false
    var onStart: (() -> Void)? = nil
    var onError: (String) -> Void = { _ in }
    var body: some View {
        if starting {
            ProgressView().controlSize(.small).help("Starting: a worktree and an agent in Orca…")
        } else if let worktree {
            QSIconButton(systemImage: "terminal",
                         help: "Go to \(worktree.name) in Orca" + (worktree.liveAgentTerminal != nil ? " (agent live)" : "")) {
                Task { do { try await Orca.go(to: worktree) } catch { onError(error.localizedDescription) } }
            }
        } else if let onStart {
            QSIconButton(systemImage: "play.circle",
                         help: "Start: /start-task opens a worktree and an agent in Orca. Work with no code gets an agent in the vault.",
                         action: onStart)
        } else {
            QSIconButton(systemImage: "terminal", help: "No Orca worktree for this issue", enabled: false) {}
        }
    }
}

struct QSColumn<Content: View>: View {
    let title: String
    let color: Color
    var count = 0
    var isEmpty = false
    /// How wide a column with cards may grow. Empty columns then take the rest, so each state keeps its place.
    var maxWidth: CGFloat = .infinity
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
        .frame(minWidth: Theme.Size.columnMin, maxWidth: maxWidth, minHeight: Theme.Size.columnMinHeight, alignment: .topLeading)
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
        .frame(minWidth: Theme.Size.columnCollapsed, maxWidth: .infinity, minHeight: Theme.Size.columnMinHeight + 80, alignment: .leading)
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

/// A keyboard key shown as a small cap, e.g. "←".
struct QSKeyHint: View {
    let text: String
    var body: some View {
        Text(text).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
            .padding(.horizontal, Theme.Space.xs + 1).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.xs).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs).strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
    }
}

/// One of the deck's decisions: icon, name and its key, tinted with its color.
struct QSDecisionButton: View {
    let title: String
    let icon: String
    let key: String
    let color: Color
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.xs + 2) {
                Image(systemName: icon).font(Theme.Text.cardTitle).frame(height: Theme.Size.decisionIcon)
                Text(title).font(Theme.Text.micro)
                QSKeyHint(text: key)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.decisionButton)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.pill(color)))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
        }
        .buttonStyle(QSHoverStyle(padding: 0, backdrop: false))
        .disabled(!enabled)
    }
}

/// The one button that matters on a screen: filled with the accent color. Dim and flat when there is nothing to do.
struct QSPrimaryButton: View {
    let title: String
    let icon: String
    var busy = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s) {
                if busy { ProgressView().controlSize(.small).tint(Theme.Palette.onAccent) }
                else { Image(systemName: icon) }
                Text(title)
            }
            .font(Theme.Text.cardTitle)
            .foregroundStyle(enabled ? Theme.Palette.onAccent : Theme.Palette.textTertiary)
            .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s + 2)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(enabled ? Theme.Palette.accent : Theme.Palette.well))
            .shadow(color: enabled ? Theme.Palette.accent.opacity(0.35) : .clear, radius: 8, y: 2)
        }
        .buttonStyle(QSHoverStyle(padding: 0, backdrop: false))
        .disabled(!enabled)
    }
}

/// Bullets of Markdown lines, one per line.
struct QSBulletList: View {
    let lines: [String]
    var secondary = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text("•").foregroundStyle(Theme.Palette.textTertiary)
                    MD(line).font(Theme.Text.body)
                        .foregroundStyle(secondary ? Theme.Palette.textSecondary : Theme.Palette.textPrimary)
                }
            }
        }
    }
}

/// A quiet one-line notice with an icon.
struct QSNote: View {
    let text: String
    var icon = "info.circle"
    var warning = false
    var body: some View {
        Label(text, systemImage: icon).font(Theme.Text.meta)
            .foregroundStyle(warning ? Theme.Palette.warning : Theme.Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One line of a result: a colored icon, what it is about, what happened, and links to it.
struct QSResultRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    var links: [URL] = []

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s + 2) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.s) {
                    Text(title).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                    ForEach(links, id: \.self) { url in
                        QSOpenLinkButton(url: url, help: url.absoluteString, padding: 1)
                    }
                }
                MD(detail).font(Theme.Text.body)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A screen with nothing in it, said kindly.
struct QSEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(Theme.Palette.textTertiary)
            Text(title).font(Theme.Text.heroTitle)
            if let subtitle { Text(subtitle).font(Theme.Text.body).foregroundStyle(Theme.Palette.textSecondary) }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.xl * 2)
    }
}

enum QSDate {
    /// Linear's and GitHub's ISO timestamps, with or without fractions of a second.
    static func parse(_ iso: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    /// "2 days ago", "3 hr. ago".
    static func ago(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    /// "Today", "Tomorrow", or "Thu 5 Nov" from Linear's yyyy-MM-dd.
    /// Linear's yyyy-MM-dd as a day.
    static func day(_ ymd: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.date(from: ymd)
    }

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

/// A local HTML page shown inside the app, like a review's flow. Links leave the page: web links open in the browser,
/// `vscode://file/…` links open the file in VS Code with the review profile.
struct QSWebPage: NSViewRepresentable {
    let file: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        load(web, context)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) { load(web, context) }

    private func load(_ web: WKWebView, _ context: Context) {
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
        guard context.coordinator.loaded != file || context.coordinator.modified != modified else { return }
        context.coordinator.loaded = file
        context.coordinator.modified = modified
        web.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loaded: URL?
        var modified: Date?

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.isFileURL && action.navigationType != .linkActivated { decisionHandler(.allow); return }
            if url.scheme == "about" || url.scheme == "data" || url.scheme == "blob" { decisionHandler(.allow); return }
            if action.navigationType == .linkActivated || url.scheme == "vscode" {
                Self.open(url); decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { Self.open(url) }
            return nil
        }

        static func open(_ url: URL) {
            if url.scheme == "vscode", url.host == "file" {
                // vscode://file/<path>:<line>[:<col>]
                var parts = url.path.split(separator: ":").map(String.init)
                var line: Int?
                while parts.count > 1, let n = Int(parts.last!) { line = n; parts.removeLast() }
                let path = parts.joined(separator: ":")
                if let code = Reviews.codeBinary {
                    let target = line.map { "\(path):\($0)" } ?? path
                    Task.detached { _ = try? await Shell.run(code, ["--profile", Reviews.vsCodeProfile, "-g", target]) }
                    return
                }
            }
            NSWorkspace.shared.open(url)
        }
    }
}
