import AppKit
import SwiftUI

/// Quicksave's design system, layer 2: components. Built only from `Theme` tokens; screens use these, not raw styling.

struct QSCard<Content: View>: View {
    var highlighted = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) { content }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(highlighted ? Theme.Palette.highlight : .clear))
            )
            .contentShape(Rectangle())
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

struct QSDot: View {
    let color: Color
    var size: CGFloat = Theme.Size.dot
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

struct QSLabel: View {
    let text: String
    var accent = false
    init(_ text: String, accent: Bool = false) { self.text = text; self.accent = accent }
    var body: some View {
        Text(text.uppercased()).font(Theme.Text.label)
            .foregroundStyle(accent ? Theme.Palette.accent : Theme.Palette.textSecondary)
    }
}

struct QSIconButton: View {
    let systemImage: String
    let help: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: systemImage) }
            .buttonStyle(.borderless)
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

/// Jumps to the issue's worktree in Orca; off when Orca links none.
struct OrcaButton: View {
    let worktree: Orca.Match?
    var onError: (String) -> Void = { _ in }
    var body: some View {
        QSIconButton(systemImage: worktree?.liveAgentTerminal != nil ? "terminal.fill" : "terminal",
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
    var isEmpty = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            HStack(spacing: Theme.Space.s) {
                QSDot(color: color)
                Text(title).font(Theme.Text.label)
            }
            content
            Spacer(minLength: 0)
        }
        .frame(minWidth: isEmpty ? Theme.Size.columnEmptyMin : Theme.Size.columnMin,
               maxWidth: isEmpty ? Theme.Size.columnEmptyMax : .infinity,
               minHeight: Theme.Size.columnMinHeight, alignment: .topLeading)
        .padding(Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.l).fill(Theme.Palette.tint(color)))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(height: Theme.Size.stripe).padding(.horizontal, Theme.Space.m)
        }
    }
}

struct QSBanner: View {
    let text: String
    var body: some View {
        HStack {
            Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.Palette.warning).font(Theme.Text.body)
            SettingsLink { Text("Open Settings") }
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
