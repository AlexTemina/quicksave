import SwiftUI

struct BoardView: View {
    @ObservedObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl + 4) {
                header
                if let error = store.error { QSBanner(text: error) }
                mainQuestBoard
                sideBoard
            }
            .padding(Theme.Space.xl)
        }
        .background(QSWindowBackground().ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today").font(Theme.Text.pageTitle)
            Spacer()
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
                    columns(count: { c in quest.pieces.filter { $0.column == c }.count }) { column in
                        ForEach(quest.pieces.filter { $0.column == column }) { piece in
                            PieceCard(piece: piece, store: store)
                        }
                    }
                }
            } else {
                QSLabel("Main Quest", icon: Theme.Icon.mainQuest, accent: true)
                Text(store.loading ? "Loading…" : "No open Main Quest.").foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private var sideBoard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            QSLabel("Side Quests", icon: Theme.Icon.sideQuests)
            QSPlaceholder(text: "Side quests will come from the morning contract.")
        }
    }

    /// Columns with cards share the width; empty ones shrink to a narrow strip.
    private func columns<Content: View>(count: @escaping (Column) -> Int, @ViewBuilder _ content: @escaping (Column) -> Content) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            ForEach(Column.allCases) { column in
                QSColumn(title: column.rawValue, color: store.color(of: column.rawValue, fallback: column.fallbackHex),
                         count: count(column), isEmpty: count(column) == 0) { content(column) }
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
                LinearButton(url: quest.url, help: "Open \(quest.identifier) in Linear")
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

struct PieceCard: View {
    let piece: Piece
    @ObservedObject var store: Store
    @State private var showDetail = false
    @State private var hovering = false

    var body: some View {
        let worktree = store.worktrees[piece.id]
        QSCard(content: {
            HStack(spacing: Theme.Space.s + 2) {
                Text(piece.id).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                ForEach(piece.pullRequests, id: \.number) { PRBadge(pr: $0, live: store.prStatus[$0.number]) }
                if worktree?.liveAgentTerminal != nil {
                    QSTag(text: "Agent", icon: Theme.Icon.agentLive, color: .green).help("A Claude agent is live in this issue's Orca worktree")
                }
                Spacer()
                HStack(spacing: Theme.Space.s) {
                    LinearButton(url: piece.url)
                    OrcaButton(worktree: worktree)
                }
                .opacity(hovering ? 1 : 0)
                .animation(Theme.Motion.hover, value: hovering)
            }
            Text(piece.tag).font(Theme.Text.cardTitle).fixedSize(horizontal: false, vertical: true)
            if !piece.step.isEmpty { MD(piece.step).font(Theme.Text.body) }
        }, onHoverChange: { hovering = $0 })
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail, arrowEdge: .bottom) {
            ScrollView {
                PieceDetail(index: (store.quest?.pieces.firstIndex { $0.id == piece.id } ?? 0) + 1, piece: piece,
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
                    LinearButton(url: piece.url)
                    OrcaButton(worktree: worktree) { orcaError = $0 }
                }
                Text(piece.title).font(Theme.Text.heroTitle).fixedSize(horizontal: false, vertical: true)
                if !piece.step.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Image(systemName: Theme.Icon.mainQuest).foregroundStyle(Theme.Palette.accent)
                        MD("Today, step \(index): " + piece.step).font(Theme.Text.body)
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
            Divider()
            HStack {
                Button("Open board") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
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
