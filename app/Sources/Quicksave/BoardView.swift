import SwiftUI

struct BoardView: View {
    @ObservedObject var store: Store

    var body: some View {
        ScrollView {
            BoardContent(store: store).padding(Theme.Space.xl)
        }
        .background(QSWindowBackground().ignoresSafeArea())
    }
}

/// The board without its scroll view, so it can also be drawn to an image.
struct BoardContent: View {
    @ObservedObject var store: Store

    var body: some View {
            VStack(alignment: .leading, spacing: Theme.Space.xl + 4) {
                header
                if let error = store.error { QSBanner(text: error) }
                if let notice = store.agentNotice { QSNote(text: notice, icon: "exclamationmark.triangle", warning: true) }
                if let quest = store.quest {
                    QSDayProgress(mainDone: quest.doneCount, mainTotal: quest.pieces.count,
                                  sideDone: store.sideQuests.filter { $0.column == .done }.count, sideTotal: store.sideQuests.count)
                }
                // Collectibles run down the side, next to both the Main Quest and the side quests.
                HStack(alignment: .top, spacing: Theme.Space.xl) {
                    VStack(alignment: .leading, spacing: Theme.Space.xl + 4) {
                        mainQuestBoard
                        SideQuestsSection(store: store)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    CollectiblesSection(store: store).frame(width: Theme.Size.collectiblesWidth)
                }
            }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today").font(Theme.Text.pageTitle)
            Spacer()
            if store.quest != nil {
                Button { store.openMorning() } label: { Label("Start the day", systemImage: Theme.Icon.morning) }
                    .buttonStyle(QSHoverStyle())
                    .help("Plan the day again, choose the game and write the standup")
            }
            if let last = store.lastRefresh { Text(last, style: .time).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary) }
            QSIconButton(systemImage: "arrow.clockwise", help: "Refresh from Linear", enabled: !store.loading) {
                Task { await store.refresh() }
            }
        }
    }

    @ViewBuilder private var mainQuestBoard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let quest = store.quest {
                QSHeroCard {
                    MainQuestHeader(quest: quest, store: store)
                    StateBoard(store: store, items: quest.pieces, column: \.column) { PieceCard(piece: $0, store: store) }
                }
            } else {
                QSHeroCard {
                    QSLabel("Main Quest", icon: Theme.Icon.mainQuest, accent: true)
                    Text(store.loading ? "Loading…" : "No open Main Quest.").font(Theme.Text.heroTitle)
                    Text("Plan the day: the Main Quest, the game and the standup.")
                        .font(Theme.Text.body).foregroundStyle(Theme.Palette.textSecondary)
                    QSPrimaryButton(title: "Start the day", icon: Theme.Icon.morning) { store.openMorning() }
                        .padding(.top, Theme.Space.s)
                }
            }
        }
    }

}

/// One column per Linear state, in Linear's colors; empty columns shrink to a narrow strip. The Main Quest's pieces
/// and the side quests use the same board.
struct StateBoard<Item: Identifiable, Card: View>: View {
    @ObservedObject var store: Store
    let items: [Item]
    let column: (Item) -> Column
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            ForEach(Column.allCases) { c in
                let inColumn = items.filter { column($0) == c }
                QSColumn(title: c.rawValue, color: store.color(of: c.rawValue, fallback: c.fallbackHex),
                         count: inColumn.count, isEmpty: inColumn.isEmpty) {
                    ForEach(inColumn) { card($0) }
                }
            }
        }
    }
}

struct MainQuestHeader: View {
    let quest: MainQuest
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                QSLabel("Main Quest", icon: Theme.Icon.mainQuest, accent: true)
                if let due = quest.dueDate {
                    Label(QSDate.friendly(due), systemImage: Theme.Icon.due).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                QSOpenLinkButton(url: quest.url, help: "Open \(quest.identifier) in Linear")
            }
            Text(quest.title).font(Theme.Text.heroTitle)
            MD(quest.done).font(Theme.Text.body).foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: Theme.Space.m) {
                QSProgress(segments: quest.pieces.map { (store.color(of: $0.stateName, fallback: $0.column.fallbackHex), $0.column == .done) })
                    .frame(maxWidth: 260)
                if quest.doneCount == quest.pieces.count && !quest.pieces.isEmpty {
                    Label("Quest complete", systemImage: Theme.Icon.questComplete).font(Theme.Text.number).foregroundStyle(.yellow)
                } else {
                    Text("\(quest.doneCount) of \(quest.pieces.count) done").font(Theme.Text.number).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .padding(.top, 2)
        }
    }
}

/// The card of a piece or a side quest: they are the same thing, only where they sit changes.
struct PieceCard: View {
    let piece: Piece
    @ObservedObject var store: Store
    /// Side quests can be taken out of today from the card.
    var onRemove: (() -> Void)? = nil
    @State private var showDetail = false
    @State private var hovering = false

    var body: some View {
        let worktree = store.worktrees[piece.id] ?? store.agentStates[piece.id]?.match
        let agent = store.agentStates[piece.id]
        QSCard(tint: agent?.tint, pulsing: agent?.state == "working", content: {
            // Code, date and badges wrap to a new line in a narrow column instead of being squeezed.
            QSFlow {
                Text(piece.id).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary).fixedSize()
                if let due = piece.dueDate { QSDue(ymd: due, done: piece.column == .done) }
                ForEach(piece.pullRequests, id: \.number) { PRBadge(pr: $0, live: store.prStatus[$0.number]).fixedSize() }
                if store.agentStates[piece.id] == nil, worktree?.liveAgentTerminal != nil {
                    QSTag(text: "Agent", icon: Theme.Icon.agentLive, color: .green).fixedSize()
                        .help("A Claude agent is live in this issue's Orca worktree")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The actions float over the corner on hover, so they take no room from the badges.
            .overlay(alignment: .topTrailing) {
                HStack(spacing: Theme.Space.s) {
                    QSOpenLinkButton(url: piece.url)
                    OrcaButton(worktree: worktree, starting: store.startingAgents.contains(piece.id),
                               onStart: { Task { await store.startAgent(piece) } })
                    if let onRemove {
                        if store.planWriting.contains(piece.id) { ProgressView().controlSize(.small) }
                        else { QSIconButton(systemImage: "minus.circle", help: "Take it out of today. The issue itself does not change.", action: onRemove) }
                    }
                }
                .padding(.horizontal, Theme.Space.xs)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.surface))
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .animation(Theme.Motion.hover, value: hovering)
                .offset(y: -2)
            }
            Text(piece.tag).font(Theme.Text.cardTitle).fixedSize(horizontal: false, vertical: true)
            if !piece.step.isEmpty { MD(piece.step).font(Theme.Text.body) }
            let steps = IssueSections(piece.description).steps
            if !steps.isEmpty {
                HStack(spacing: Theme.Space.s) {
                    QSProgress(segments: steps.map { (Theme.Palette.questMain, $0.done) }, height: Theme.Size.miniBarHeight)
                    Text("\(steps.filter(\.done).count)/\(steps.count)").font(Theme.Text.micro).foregroundStyle(Theme.Palette.textTertiary)
                }
                .help("Actions done in the issue")
            }
        }, onHoverChange: { hovering = $0 })
        .help(agent.map { a in a.lastMessage.isEmpty ? a.name : "Agent: " + String(a.lastMessage.prefix(300)) } ?? "")
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail, arrowEdge: .bottom) {
            ScrollView {
                PieceDetail(index: ((piece.isSide ? store.sideQuests : store.quest?.pieces ?? []).firstIndex { $0.id == piece.id } ?? 0) + 1, piece: piece,
                            color: store.color(of: piece.stateName, fallback: piece.column.fallbackHex), worktree: worktree,
                            store: store)
            }
            .padding(Theme.Space.xl)
            .frame(width: Theme.Size.popoverWidth)
            .frame(maxHeight: Theme.Size.popoverMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A piece's issue, read through the house template: what it is about, what to do, how to prove it.
struct PieceDetail: View {
    let index: Int
    let piece: Piece
    let color: Color
    let worktree: Orca.Match?
    @ObservedObject var store: Store
    @State private var orcaError: String?
    @State private var showMore = false

    var body: some View {
        let sections = IssueSections(piece.description)
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.s) {
                    Text(piece.id).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                    QSPill(text: piece.stateName, color: color)
                    ForEach(piece.pullRequests, id: \.number) { PRBadge(pr: $0, live: store.prStatus[$0.number]) }
                    Spacer()
                    QSOpenLinkButton(url: piece.url)
                    OrcaButton(worktree: worktree, starting: store.startingAgents.contains(piece.id),
                               onStart: { Task { await store.startAgent(piece) } }, onError: { orcaError = $0 })
                }
                Text(piece.title).font(Theme.Text.heroTitle).fixedSize(horizontal: false, vertical: true)
                if let agent = store.agentStates[piece.id] {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        HStack(spacing: Theme.Space.s) {
                            QSLabel("Agent", icon: Theme.Icon.agentLive)
                            QSAgentTag(agent: agent)
                            if agent.updatedAt > 0 {
                                Text(QSDate.ago(Date(timeIntervalSince1970: agent.updatedAt / 1000)))
                                    .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                        if !agent.lastMessage.isEmpty {
                            MarkdownBlock(String(agent.lastMessage.prefix(900))).font(Theme.Text.meta)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                    .padding(Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.well))
                }
                if !piece.step.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Image(systemName: Theme.Icon.mainQuest).foregroundStyle(Theme.Palette.accent)
                        MD((piece.isSide ? "Today, side quest: " : "Today, step \(index): ") + piece.step).font(Theme.Text.body)
                    }
                }
            }

            if !sections.context.isEmpty || !sections.goal.isEmpty {
                DetailSection(title: "Context", icon: "text.alignleft") {
                    if !sections.context.isEmpty { MarkdownBlock(sections.context).font(Theme.Text.body) }
                    if !sections.goal.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            QSLabel("Goal", icon: "scope")
                            MarkdownBlock(sections.goal).font(Theme.Text.body)
                        }
                        .padding(Theme.Space.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.well))
                        .padding(.top, Theme.Space.s)
                    }
                }
            }

            if !sections.steps.isEmpty {
                DetailSection(title: "Actions", icon: "list.bullet", trailing: progress(sections.steps)) {
                    ChecklistView(items: sections.steps)
                }
            }

            if !sections.watchOut.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    QSLabel("Watch out", icon: "exclamationmark.triangle")
                    MarkdownBlock(sections.watchOut).font(Theme.Text.body)
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.warning.opacity(0.10)))
            }

            if !sections.qa.isEmpty {
                DetailSection(title: "QA", icon: "checkmark.seal", trailing: progress(sections.qa)) {
                    ChecklistView(items: sections.qa)
                }
            }

            if !sections.other.isEmpty {
                Button { showMore.toggle() } label: {
                    Label(showMore ? "Less" : "More: " + sections.other.map(\.title).joined(separator: ", "),
                          systemImage: showMore ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(QSHoverStyle(padding: 2)).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                if showMore {
                    ForEach(Array(sections.other.enumerated()), id: \.offset) { _, sec in
                        DetailSection(title: sec.title, icon: "doc.text") { MarkdownBlock(sec.body).font(Theme.Text.meta) }
                    }
                }
            }
            if let orcaError { Text(orcaError).font(Theme.Text.meta).foregroundStyle(Theme.Palette.warning) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progress(_ items: [IssueSections.Item]) -> String {
        "\(items.filter(\.done).count)/\(items.count)"
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    let icon: String
    var trailing: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                QSLabel(title, icon: icon)
                Spacer()
                if let trailing { Text(trailing).font(Theme.Text.label).foregroundStyle(Theme.Palette.textTertiary) }
            }
            content
        }
    }
}

struct ChecklistView: View {
    let items: [IssueSections.Item]
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.done ? Theme.Palette.prOpen : Theme.Palette.textTertiary)
                    MD(item.text).font(Theme.Text.body)
                        .foregroundStyle(item.done ? Theme.Palette.textSecondary : Theme.Palette.textPrimary)
                        .strikethrough(item.done, color: Theme.Palette.textTertiary)
                }
            }
        }
    }
}

struct MenuView: View {
    @ObservedObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            if let q = store.quest {
                Text(q.title).font(Theme.Text.cardTitle)
                if let n = q.next { Text("Next: \(n.id) (\(n.tag))").font(Theme.Text.body) }
                Text("\(q.doneCount)/\(q.pieces.count) done").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
            } else {
                Text(store.error ?? "No open Main Quest.").font(Theme.Text.body).foregroundStyle(Theme.Palette.textSecondary)
            }
            if !store.pendingCards.isEmpty {
                Button {
                    store.tab = .inbox
                    openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
                } label: { Label("Inbox: \(store.pendingCards.count) to decide", systemImage: Theme.Icon.inbox) }
                    .buttonStyle(QSHoverStyle())
            }
            Button {
                store.tab = .today
                store.openMorning()
                openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
            } label: { Label("Start the day", systemImage: Theme.Icon.morning) }
                .buttonStyle(QSHoverStyle())
            Divider()
            HStack {
                Button("Open board") {
                    store.tab = .today
                    openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
                }
                    .buttonStyle(QSHoverStyle())
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(QSHoverStyle())
                QSIconButton(systemImage: "arrow.clockwise", help: "Refresh from Linear") { Task { await store.refresh() } }
            }
        }
        .padding(Theme.Space.m + 2)
        .frame(width: 300)
        .onAppear { Task { await store.refresh() } }
    }
}
