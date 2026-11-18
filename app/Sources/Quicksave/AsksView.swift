import SwiftUI

/// "Asked of me": every place someone asked him something by name, whether he already answered there, and the card
/// that follows it up, with a button to file one when there is none. See docs/asks.md.
struct AsksView: View {
    @ObservedObject var store: Store

    var body: some View {
        ScrollView { AsksContent(store: store) }
            .background(QSWindowBackground())
    }
}

struct AsksContent: View {
    @ObservedObject var store: Store
    @State private var showAnswered = false

    var body: some View {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                header
                if let e = store.asksError { QSNote(text: e, icon: "exclamationmark.triangle", warning: true) }
                let waiting = store.waitingAsks
                let rest = store.visibleAsks.filter { a in !waiting.contains { $0.id == a.id } }
                if waiting.isEmpty {
                    QSEmptyState(icon: "checkmark.bubble", title: "Nobody is waiting on you",
                                 subtitle: store.asks.isEmpty && store.asksLoading ? "Reading GitHub and Linear…" : "Every mention of the last two weeks is answered or has a closed card.")
                        .padding(.vertical, Theme.Space.l)
                } else {
                    QSLabel("Waiting on you · \(waiting.count)", icon: "person.wave.2").padding(.top, Theme.Space.s)
                    ForEach(waiting) { AskRow(ask: $0, store: store) }
                }
                if !rest.isEmpty {
                    Button { showAnswered.toggle() } label: {
                        QSLabel("Answered or closed · \(rest.count)", icon: showAnswered ? "chevron.down" : "chevron.right")
                    }
                    .buttonStyle(.plain).padding(.top, Theme.Space.m)
                    if showAnswered { ForEach(rest) { AskRow(ask: $0, store: store, quiet: true) } }
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text("Asked of me").font(Theme.Text.pageTitle)
            Spacer()
            if store.asksAgentRunning {
                QSTag(text: "Reading Slack, mail and Notion", icon: Theme.Icon.agentLive, color: Theme.Palette.agentWorking)
            } else if let at = store.asksAgentLooked {
                Text("Slack, mail and Notion read \(QSDate.ago(at))").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary)
            }
            if store.asksLoading { ProgressView().controlSize(.small) }
            QSIconButton(systemImage: "arrow.clockwise", help: "Read GitHub, Linear, Slack, mail and Notion again") {
                Task { if let key = Database.shared.secret("linearApiKey") { await store.refreshAsks(key: key, force: true) } }
            }
            if !store.dismissedAsks.isEmpty {
                QSIconButton(systemImage: "eye", help: "Show the \(store.dismissedAsks.count) dismissed again") { store.undismissAll() }
            }
        }
    }
}

struct AskRow: View {
    let ask: Ask
    @ObservedObject var store: Store
    var quiet = false
    @State private var hovering = false

    var body: some View {
        let card = store.askCards[ask.id]
        QSCard(dashed: quiet, content: {
            QSFlow {
                QSTag(text: ask.cardOrigin.rawValue, icon: ask.cardOrigin.icon, color: Theme.Palette.textSecondary).fixedSize()
                Text(ask.who).font(Theme.Text.label).fixedSize()
                if let d = ask.date { Text(QSDate.ago(d)).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary).fixedSize() }
                if ask.answered {
                    QSTag(text: "You answered", icon: "checkmark", color: Theme.Palette.prOpen).fixedSize()
                }
                if let deadline = ask.deadline, !ask.answered {
                    QSTag(text: deadline, icon: Theme.Icon.due, color: Theme.Palette.warning).fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                QSHoverActions(visible: hovering) {
                    QSOpenLinkButton(url: URL(string: ask.url), help: "Open where it was asked")
                    QSIconButton(systemImage: "eye.slash", help: "Not for me, or answered somewhere else: hide it") { store.dismissAsk(ask) }
                }
            }
            Text(ask.place).font(Theme.Text.cardTitle).lineLimit(2)
                .foregroundStyle(quiet ? Theme.Palette.textSecondary : Theme.Palette.textPrimary)
            if !ask.text.isEmpty {
                MD(ask.text).font(Theme.Text.body).foregroundStyle(Theme.Palette.textSecondary).lineLimit(4)
            }
            HStack(spacing: Theme.Space.s) {
                if let card {
                    QSLinkButton(url: URL(string: card.url), help: "Open the card in Linear") {
                        HStack(spacing: Theme.Space.xs) {
                            if let k = card.kind { QSKindTag(kind: k) }
                            Text(card.identifier).font(Theme.Text.code)
                            QSPill(text: card.stateName, color: store.color(of: card.stateName, fallback: Column.of(name: card.stateName, type: card.stateType).fallbackHex))
                        }
                    }
                } else if store.creatingCard.contains(ask.id) {
                    ProgressView().controlSize(.small)
                    Text("Filing the card…").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Text("No card").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary)
                    Button { Task { await store.createCard(for: ask) } } label: {
                        Label("Create card", systemImage: "plus.square.on.square").font(Theme.Text.label)
                    }
                    .buttonStyle(.borderless)
                    .help("Files a TEMI card in Todo, due today, with the ask, its link and who asked")
                }
                Spacer(minLength: 0)
            }
        }, onHoverChange: { hovering = $0 })
    }
}
