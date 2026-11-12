import AppKit
import SwiftUI

/// The one way to talk to an AI in Quicksave: what it does and may touch, the conversation, what it is doing right
/// now, its proposal shown as it will look, a reply box, and one button that accepts. Every place where he writes a
/// prompt uses it. See docs/design-system.md.
struct QSConversationTurn: Identifiable, Hashable {
    enum Who: Hashable {
        /// What he wrote.
        case me
        /// A short line from the AI: what it changed, what it did.
        case ai
        /// The AI needs something from him before it can go on.
        case question
        /// Something that happened, not said by anyone: he used a version, went back, edited by hand.
        case event
    }
    let id: Int64
    let who: Who
    let text: String
    /// What the AI proposes with this turn (a new text, a plan), shown under it.
    var proposal: String? = nil
    /// A short label for the proposal, like "v3".
    var label: String? = nil
}

struct QSConversation<Proposal: View>: View {
    /// One sentence: what the AI does here and what it may touch.
    let purpose: String
    let turns: [QSConversationTurn]
    let busy: Bool
    /// What it is doing right now, in a few words.
    var step: String? = nil
    var quick: [String] = []
    let placeholder: String
    let send: (String) -> Void
    /// The turn whose proposal waits for him, and the button that accepts it.
    var pendingId: Int64? = nil
    var acceptTitle = "Use this"
    var accept: () -> Void = {}
    @ViewBuilder let proposal: (String) -> Proposal

    @State private var text = ""

    private var waitingOnHim: Bool { !busy && turns.last?.who == .question }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Label(purpose, systemImage: "sparkles")
                .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
            if !turns.isEmpty || busy {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            ForEach(turns) { turnView($0) }
                            if busy { stepRow }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, Theme.Space.s)
                    }
                    .frame(maxHeight: Theme.Size.conversationMaxHeight)
                    .fixedSize(horizontal: false, vertical: true)
                    .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                    .onChange(of: turns.count) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                    .onChange(of: busy) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                }
            }
            if !quick.isEmpty {
                HStack(spacing: Theme.Space.s) {
                    ForEach(quick, id: \.self) { q in
                        Button(q) { send(q) }.buttonStyle(QSHoverStyle()).font(Theme.Text.meta).disabled(busy)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: Theme.Space.s) {
                QSPromptField(text: $text, placeholder: waitingOnHim ? "Answer its question" : placeholder,
                              enabled: !busy, submit: submit)
                    .padding(Theme.Space.s)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.well))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .strokeBorder(waitingOnHim ? Theme.Palette.agentAsking : .clear, lineWidth: 1.2))
                Button("Send", action: submit)
                    .buttonStyle(QSHoverStyle()).foregroundStyle(Theme.Palette.accent)
                    .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Return sends, Shift-Return adds a line.")
                .font(Theme.Text.micro).foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.raised))
    }

    private func submit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !t.isEmpty else { return }
        text = ""
        send(t)
    }

    private var stepRow: some View {
        HStack(spacing: Theme.Space.s) {
            ProgressView().controlSize(.small)
            Text((step ?? "Working") + "…")
                .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                .contentTransition(.opacity)
                .animation(Theme.Motion.hover, value: step)
        }
    }

    @ViewBuilder private func turnView(_ t: QSConversationTurn) -> some View {
        switch t.who {
        case .me:
            HStack {
                Spacer(minLength: Theme.Space.xl * 2)
                Text(t.text).font(Theme.Text.body).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.accent.opacity(0.12)))
            }
        case .event:
            Label(t.text, systemImage: "arrow.uturn.backward")
                .font(Theme.Text.micro).foregroundStyle(Theme.Palette.textTertiary)
        case .question:
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(Theme.Palette.agentAsking)
                Text(t.text).font(Theme.Text.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.agentAsking.opacity(0.10)))
        case .ai:
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.Palette.accent)
                    Text(t.text).font(Theme.Text.body).foregroundStyle(Theme.Palette.textSecondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let label = t.label { Text(label).font(Theme.Text.code).foregroundStyle(Theme.Palette.textTertiary) }
                }
                if let p = t.proposal {
                    let pending = t.id == pendingId
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        proposal(p)
                        if pending {
                            HStack {
                                Text("Not used yet: the draft keeps its text until you use this.")
                                    .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                                Spacer()
                                QSPrimaryButton(title: acceptTitle, icon: "checkmark", enabled: !busy, action: accept)
                            }
                        }
                    }
                    .padding(Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.surface))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .strokeBorder(pending ? Theme.Palette.accent.opacity(0.6) : Theme.Palette.hairline, lineWidth: pending ? 1.2 : 0.5))
                    .opacity(pending || pendingId == nil ? 1 : 0.75)
                }
            }
        }
    }
}

/// A prompt box: Return sends, Shift-Return adds a line. It grows with the text up to a few lines, then scrolls.
struct QSPromptField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var enabled = true
    let submit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        tv.isEditable = enabled
        tv.textColor = enabled ? .labelColor : .secondaryLabelColor
        context.coordinator.placeholder.stringValue = placeholder
        context.coordinator.placeholder.isHidden = !text.isEmpty
        if context.coordinator.placeholder.superview == nil {
            let p = context.coordinator.placeholder
            p.translatesAutoresizingMaskIntoConstraints = false
            tv.addSubview(p)
            NSLayoutConstraint.activate([
                p.leadingAnchor.constraint(equalTo: tv.leadingAnchor, constant: 5),
                p.topAnchor.constraint(equalTo: tv.topAnchor, constant: 2),
            ])
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let tv = nsView.documentView as? NSTextView, let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
        let width = proposal.width ?? 400
        tc.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
        let line = (tv.font?.boundingRectForFont.height ?? 16)
        return CGSize(width: width, height: min(max(used, line * 2.2), line * 9))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QSPromptField
        weak var textView: NSTextView?
        let placeholder: NSTextField = {
            let f = NSTextField(labelWithString: "")
            f.textColor = .placeholderTextColor
            f.font = NSFont.systemFont(ofSize: 13)
            return f
        }()

        init(_ parent: QSPromptField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            placeholder.isHidden = !tv.string.isEmpty
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                parent.submit()
            }
            return true
        }
    }
}
