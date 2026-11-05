import SwiftUI

struct BoardView: View {
    @ObservedObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header
                if let error = store.error { QSBanner(text: error) }
                mainQuestBoard
                sideBoard
            }
            .padding(Theme.Space.xl - 4)
        }
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
                MainQuestHeader(quest: quest, store: store)
                columns(count: { c in quest.pieces.filter { $0.column == c }.count }) { column in
                    ForEach(quest.pieces.filter { $0.column == column }) { piece in
                        PieceCard(piece: piece, isNext: piece.id == quest.next?.id, store: store)
                    }
                }
            } else {
                QSLabel("Main Quest", accent: true)
                Text(store.loading ? "Loading…" : "No open Main Quest.").foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private var sideBoard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            QSLabel("Side Quests")
            columns(count: { _ in 0 }) { _ in EmptyView() }
            Text("Filled by the morning contract, not built yet.").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    /// Columns with cards share the width; empty ones shrink to a narrow strip.
    private func columns<Content: View>(count: @escaping (Column) -> Int, @ViewBuilder _ content: @escaping (Column) -> Content) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            ForEach(Column.allCases) { column in
                QSColumn(title: column.rawValue, color: store.color(of: column.rawValue, fallback: column.fallbackHex),
                         isEmpty: count(column) == 0) { content(column) }
            }
        }
    }
}

struct MainQuestHeader: View {
    let quest: MainQuest
    @ObservedObject var store: Store

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Space.s + 2) {
                    QSLabel("Main Quest", accent: true)
                    QSPill(text: quest.stateName, color: store.color(of: quest.stateName, fallback: quest.column.fallbackHex))
                }
                Text(quest.title).font(Theme.Text.sectionTitle)
                MD(quest.done).font(Theme.Text.body).foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(quest.doneCount)/\(quest.pieces.count) done").font(Theme.Text.number)
                if let due = quest.dueDate { Text("Ends \(due)").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary) }
            }
            LinearButton(url: quest.url, help: "Open \(quest.identifier) in Linear")
        }
    }
}

struct PieceCard: View {
    let piece: Piece
    let isNext: Bool
    @ObservedObject var store: Store
    @State private var showDetail = false

    var body: some View {
        let worktree = store.worktrees[piece.id]
        QSCard(highlighted: isNext) {
            HStack(spacing: Theme.Space.s + 2) {
                Text(piece.id).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                LinearButton(url: piece.url)
                OrcaButton(worktree: worktree)
            }
            Text(piece.tag).font(Theme.Text.cardTitle).fixedSize(horizontal: false, vertical: true)
            if !piece.step.isEmpty { MD(piece.step).font(Theme.Text.body) }
            if !piece.qa.isEmpty {
                Label("QA · \(piece.qa.count)", systemImage: "checklist").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail, arrowEdge: .bottom) {
            ScrollView {
                PieceDetail(index: (store.quest?.pieces.firstIndex { $0.id == piece.id } ?? 0) + 1, piece: piece,
                            color: store.color(of: piece.stateName, fallback: piece.column.fallbackHex), worktree: worktree)
            }
            .padding(Theme.Space.m + 2)
            .frame(width: Theme.Size.popoverWidth)
            .frame(maxHeight: Theme.Size.popoverMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PieceDetail: View {
    let index: Int
    let piece: Piece
    let color: Color
    let worktree: Orca.Match?
    @State private var showDescription = false
    @State private var orcaError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s + 2) {
                Text("\(index).").font(Theme.Text.cardTitle).foregroundStyle(Theme.Palette.textSecondary)
                Text(piece.id).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                Text(piece.tag).font(Theme.Text.cardTitle)
                QSPill(text: piece.stateName, color: color)
                Spacer()
                LinearButton(url: piece.url)
                OrcaButton(worktree: worktree) { orcaError = $0 }
            }
            if !piece.step.isEmpty { MD(piece.step).font(Theme.Text.body) }
            if !piece.qa.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    QSLabel("QA")
                    ForEach(piece.qa, id: \.self) { MD("☐ " + $0).font(Theme.Text.meta) }
                }
            }
            Button(showDescription ? "Hide issue" : "Show issue") { showDescription.toggle() }
                .buttonStyle(.link).font(Theme.Text.meta)
            if showDescription { MarkdownBlock(piece.description).font(Theme.Text.meta) }
            if let orcaError { Text(orcaError).font(Theme.Text.meta).foregroundStyle(Theme.Palette.warning) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                QSIconButton(systemImage: "arrow.clockwise", help: "Refresh from Linear") { Task { await store.refresh() } }
            }
        }
        .padding(Theme.Space.m + 2)
        .frame(width: 300)
        .onAppear { Task { await store.refresh() } }
    }
}
