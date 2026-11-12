import AppKit
import SwiftUI

/// The inbox: everything waiting for a decision, one card at a time, made to go fast with the keyboard.
struct InboxView: View {
    @ObservedObject var store: Store
    @FocusState private var deckFocused: Bool
    @FocusState private var editorFocused: Bool
    @State private var editing = false
    @State private var draft = ""
    @State private var newDate = Date()
    /// Editing an expired card's instruction rather than its date.
    @State private var instructing = false
    @State private var exit: Choice?

    /// What a press does to the current card. The card flies off to the side of its meaning.
    enum Choice: Equatable {
        case accept, reject, done, later, backlog, correct(String), instruct(String)

        var offset: CGSize {
            switch self {
            case .accept, .correct, .instruct: return CGSize(width: 560, height: 0)
            case .reject: return CGSize(width: -560, height: 0)
            case .done, .backlog: return CGSize(width: 0, height: 420)
            case .later: return CGSize(width: 0, height: -60)
            }
        }
        var rotation: Double {
            switch self {
            case .accept, .correct, .instruct: return 7
            case .reject: return -7
            default: return 0
            }
        }
    }

    var body: some View {
        // The page never scrolls: the header and the decisions keep their place, and the card takes the space
        // between them. A card too tall for it scrolls inside its own frame, so it is never cut off.
        VStack(spacing: Theme.Space.l) {
            header
            if let error = store.inboxError { QSNote(text: error, icon: "exclamationmark.triangle", warning: true) }
            if let notice = store.inboxNotice { QSNote(text: notice, icon: "exclamationmark.triangle", warning: true) }
            ForEach(store.instructionResults.prefix(3), id: \.self) { QSNote(text: $0, icon: "checkmark.circle") }
            Group { if let card = store.currentCard { deck(card) } else { emptyState } }
                .frame(maxHeight: .infinity, alignment: .top)
            VStack(spacing: Theme.Space.l) {
                if let card = store.currentCard {
                    if editing { editorActions } else { decisionBar(for: card) }
                }
                footer
            }
        }
        .frame(maxWidth: Theme.Size.deckWidth)
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.xl).padding(.bottom, Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QSWindowBackground().ignoresSafeArea())
        .sheet(item: $store.report) { report in
            ApplyReportView(report: report, openDrafts: { store.report = nil; store.tab = .drafts })
        }
        .focusable()
        .focused($deckFocused)
        .focusEffectDisabled()
        .onAppear { deckFocused = true }
        .onKeyPress(KeyEquivalent("d")) { act(.accept) }
        .onKeyPress(KeyEquivalent("a")) { act(.reject) }
        .onKeyPress(KeyEquivalent("q")) { act(.done) }
        .onKeyPress(.space) { act(.later) }
        .onKeyPress(KeyEquivalent("e")) { beginEdit() ? .handled : .ignored }
        .onKeyPress(KeyEquivalent("r")) { beginInstruct() ? .handled : .ignored }
        .onKeyPress(KeyEquivalent("w")) {
            guard case .expired? = store.currentCard else { return .ignored }
            return act(.backlog)
        }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Inbox").font(Theme.Text.pageTitle)
            Spacer()
            if !store.pendingCards.isEmpty {
                Text("\(store.pendingCards.count) to decide").font(Theme.Text.number).foregroundStyle(Theme.Palette.textSecondary)
            }
            QSIconButton(systemImage: "arrow.clockwise", help: "Refresh", enabled: !store.loading) { Task { await store.refresh() } }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.m) {
            Button { store.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .buttonStyle(QSHoverStyle())
                .keyboardShortcut("z", modifiers: .command)
                .disabled(store.lastDecided == nil || store.applying)
            if let last = store.lastDecided {
                Text("\(last.decision.verb): \(last.card.label)").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
            if !store.writing.isEmpty { ProgressView().controlSize(.small).help("Saving to Linear") }
            Spacer()
            if store.applying {
                Text(store.applyStep.isEmpty ? "This can take a few minutes" : store.applyStep)
                    .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
            } else if store.applyCount > 0 {
                Text("\(store.applyCount) waiting to be executed").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
            }
            QSPrimaryButton(title: store.applying ? "Applying…" : "Apply \(store.applyCount)", icon: "bolt.fill",
                            busy: store.applying,
                            enabled: store.applyCount > 0 && !store.applying && store.writing.isEmpty) { Task { await store.apply() } }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .help("Executes what you accepted: merges or closes pull requests, and starts one agent for the items in Todo. ⌘⇧↩")
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !store.inboxLoaded {
            QSEmptyState(icon: Theme.Icon.inbox, title: "Loading…")
        } else if store.inbox.isEmpty {
            QSEmptyState(icon: Theme.Icon.inbox, title: "Nothing is waiting for you",
                         subtitle: "Triage and the vault's pull requests are empty.")
        } else {
            QSEmptyState(icon: Theme.Icon.questComplete, title: "All decided",
                         subtitle: "\(store.decisions.count) decisions. \(store.applyCount) will be applied.")
        }
    }

    // MARK: The deck

    private func deck(_ card: InboxCard) -> some View {
        let behind = min(2, store.pendingCards.count - 1)
        return Group {
            if editing, case .triage(let item) = card { editor(for: item) }
            else if editing, instructing, case .expired(let item) = card { instructionEditor(for: item) }
            else if editing, case .expired(let item) = card { dateEditor(for: item) }
            else { cardView(card) }
        }
        .background(alignment: .top) {
            ForEach(0..<max(behind, 0), id: \.self) { i in
                RoundedRectangle(cornerRadius: Theme.Radius.xl).fill(Theme.Palette.raised)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl).strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
                    .padding(.horizontal, Theme.Space.l * CGFloat(i + 1))
                    .offset(y: Theme.Space.m * CGFloat(i + 1))
            }
        }
        .padding(.bottom, Theme.Space.m * CGFloat(max(behind, 0)))
        .id(card.id)
        .offset(exit?.offset ?? .zero)
        .rotationEffect(.degrees(exit?.rotation ?? 0))
        .opacity(exit == nil ? 1 : 0)
        .transition(.opacity)
    }

    @ViewBuilder private func cardView(_ card: InboxCard) -> some View {
        switch card {
        case .triage(let item): TriageCardView(item: item)
        case .pullRequest(let pr): PullRequestCardView(pr: pr)
        case .expired(let e): ExpiredCardView(item: e)
        }
    }

    /// What to do with an expired issue, in his words.
    private func instructionEditor(for item: ExpiredItem) -> some View {
        QSDeckCard {
            HStack {
                QSLabel("Tell it what to do", icon: "text.bubble", accent: true)
                Spacer()
                Text(item.id).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
            }
            Text(item.issue.title).font(Theme.Text.cardTitle).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $draft)
                .font(Theme.Text.body)
                .scrollContentBackground(.hidden)
                .padding(Theme.Space.s)
                .frame(minHeight: Theme.Size.editorMinHeight)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.well))
                .focused($editorFocused)
            Text("For example: reassign it to Gonzalo and draft him a Slack message. An agent does it in Linear; any message comes back as a draft.")
                .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    /// A new due date for an expired issue: one more postpone.
    private func dateEditor(for item: ExpiredItem) -> some View {
        QSDeckCard {
            HStack {
                QSLabel("New date", icon: "calendar", accent: true)
                Spacer()
                Text(item.id).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
            }
            Text(item.issue.title).font(Theme.Text.cardTitle).fixedSize(horizontal: false, vertical: true)
            DatePicker("Due", selection: $newDate, in: Date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(maxWidth: 320)
            Text("Postpone \(item.postpones + 1) of \(ExpiredItem.maxPostpones). After the third, it can only be done, sent to the backlog or canceled.")
                .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private func editor(for item: TriageItem) -> some View {
        QSDeckCard {
            HStack {
                QSLabel("Edit what will be done", icon: Theme.Icon.correct, accent: true)
                Spacer()
                Text(item.id).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
            }
            Text(item.title).font(Theme.Text.cardTitle).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $draft)
                .font(Theme.Text.body)
                .scrollContentBackground(.hidden)
                .padding(Theme.Space.s)
                .frame(minHeight: Theme.Size.editorMinHeight)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.well))
                .focused($editorFocused)
            Text("One line per action. Type it or dictate it.").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var editorActions: some View {
        HStack(spacing: Theme.Space.m) {
            Button("Cancel") { stopEditing() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(QSHoverStyle())
            Spacer()
            if instructing {
                Button {
                    act(.instruct(draft))
                } label: { Label("Do it", systemImage: "paperplane") }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(QSHoverStyle())
                    .foregroundStyle(Theme.Palette.decisionAccept)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else if case .expired? = store.currentCard {
                Button {
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
                    act(.correct(f.string(from: newDate)))
                } label: { Label("Move to this date", systemImage: "calendar") }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(QSHoverStyle())
                    .foregroundStyle(Theme.Palette.decisionAccept)
            } else {
                Button {
                    act(.correct(draft))
                } label: { Label("Accept with this", systemImage: Theme.Icon.accept) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(QSHoverStyle())
                    .foregroundStyle(Theme.Palette.decisionAccept)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder private func decisionBar(for card: InboxCard) -> some View {
        if case .expired(let item) = card { expiredBar(for: item) } else { reviewBar(for: card) }
    }

    /// An expired issue: cancel, done, later, backlog, a new date (until the third postpone) or today.
    private func expiredBar(for item: ExpiredItem) -> some View {
        HStack(spacing: Theme.Space.m) {
            QSDecisionButton(title: "Cancel", icon: Theme.Icon.reject, key: "A", color: Theme.Palette.decisionReject) { act(.reject) }
            QSDecisionButton(title: "Already done", icon: Theme.Icon.alreadyDone, key: "Q", color: Theme.Palette.decisionDone) { act(.done) }
            QSDecisionButton(title: "Later", icon: Theme.Icon.later, key: "space", color: Theme.Palette.decisionLater) { act(.later) }
            QSDecisionButton(title: "Backlog", icon: "tray.and.arrow.down", key: "W", color: Theme.Palette.decisionLater) { act(.backlog) }
            QSDecisionButton(title: "Tell it", icon: "text.bubble", key: "R", color: Theme.Palette.decisionCorrect) { _ = beginInstruct() }
                .help("Say what to do, like reassigning it to someone. An agent does it in Linear.")
            QSDecisionButton(title: "New date", icon: "calendar", key: "E", color: Theme.Palette.decisionCorrect, enabled: item.canPostpone) { _ = beginEdit() }
                .help(item.canPostpone ? "Postpone it: \(item.postpones) of \(ExpiredItem.maxPostpones) used" : "Postponed \(item.postpones) times: do it, drop it or close it")
            QSDecisionButton(title: "Today", icon: Theme.Icon.accept, key: "D", color: Theme.Palette.decisionAccept) { act(.accept) }
        }
    }

    private func reviewBar(for card: InboxCard) -> some View {
        var canCorrect = false
        if case .triage = card { canCorrect = true }
        return HStack(spacing: Theme.Space.m) {
            QSDecisionButton(title: "Reject", icon: Theme.Icon.reject, key: "A", color: Theme.Palette.decisionReject) { act(.reject) }
            QSDecisionButton(title: "Already done", icon: Theme.Icon.alreadyDone, key: "Q", color: Theme.Palette.decisionDone) { act(.done) }
            QSDecisionButton(title: "Later", icon: Theme.Icon.later, key: "space", color: Theme.Palette.decisionLater) { act(.later) }
            QSDecisionButton(title: "Correct", icon: Theme.Icon.correct, key: "E", color: Theme.Palette.decisionCorrect, enabled: canCorrect) { _ = beginEdit() }
            QSDecisionButton(title: card.isPullRequest ? "Merge" : "Accept", icon: Theme.Icon.accept, key: "D", color: Theme.Palette.decisionAccept) { act(.accept) }
        }
    }

    // MARK: Actions

    @discardableResult private func act(_ choice: Choice) -> KeyPress.Result {
        guard let card = store.currentCard, exit == nil else { return .ignored }
        if editing, case .correct = choice {} else if editing, case .instruct = choice {} else if editing { return .ignored }
        withAnimation(.easeIn(duration: 0.16)) { exit = choice }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 170_000_000)
            switch choice {
            case .accept: store.decide(card, .accept)
            case .correct(let text): store.decide(card, .correct(text))
            case .reject: store.decide(card, .reject)
            case .done: store.decide(card, .alreadyDone)
            case .later: store.later(card)
            case .backlog: store.decide(card, .backlog)
            case .instruct(let text): store.decide(card, .instruct(text))
            }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { exit = nil; editing = false; instructing = false }
            deckFocused = true
        }
        return .handled
    }

    private func beginInstruct() -> Bool {
        guard !editing, case .expired? = store.currentCard else { return false }
        draft = ""
        instructing = true
        editing = true
        editorFocused = true
        return true
    }

    private func beginEdit() -> Bool {
        if !editing, case .expired(let item)? = store.currentCard {
            guard item.canPostpone else { return false }
            newDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            editing = true
            return true
        }
        guard !editing, case .triage(let item)? = store.currentCard else { return false }
        draft = item.willDo.map { "- " + $0 }.joined(separator: "\n")
        editing = true
        editorFocused = true
        return true
    }

    private func stopEditing() {
        editing = false
        instructing = false
        deckFocused = true
    }
}

extension InboxCard {
    var isPullRequest: Bool { if case .pullRequest = self { return true } else { return false } }
}

/// What applying did, item by item, and the drafts it left for him to post.
struct ApplyReportView: View {
    let report: ApplyReport
    let openDrafts: () -> Void
    @Environment(\.dismiss) private var dismiss

    private func icon(_ o: ApplyReport.Outcome) -> (String, Color) {
        switch o {
        case .done: return ("checkmark.circle.fill", Theme.Palette.prOpen)
        case .needsYou: return ("exclamationmark.circle.fill", Theme.Palette.warning)
        case .failed: return ("xmark.octagon.fill", Theme.Palette.prFailing)
        case .skipped: return ("minus.circle", Theme.Palette.textTertiary)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Applied").font(Theme.Text.pageTitle)
                    Spacer()
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(QSHoverStyle())
                }
                let done = report.rows.filter { $0.outcome == .done }.count
                Text("\(done) of \(report.rows.count) done" + (report.drafts.isEmpty ? "" : ", \(report.drafts.count) draft\(report.drafts.count == 1 ? "" : "s") for you"))
                    .font(Theme.Text.number).foregroundStyle(Theme.Palette.textSecondary)

                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(report.rows) { row in
                        let (name, color) = icon(row.outcome)
                        HStack(alignment: .top) {
                            QSResultRow(icon: name, color: color, title: row.ref, detail: row.summary, links: row.links)
                            if let worktree = row.worktree { OrcaButton(worktree: worktree) }
                        }
                    }
                }

                if !report.drafts.isEmpty {
                    HStack(spacing: Theme.Space.m) {
                        Label("\(report.drafts.count) draft\(report.drafts.count == 1 ? "" : "s") added to Drafts",
                              systemImage: "square.and.pencil")
                            .font(Theme.Text.body)
                        Spacer()
                        Button("Open Drafts") { openDrafts() }.buttonStyle(QSHoverStyle())
                    }
                    .padding(Theme.Space.m)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.well))
                }

                if !report.notes.isEmpty { QSNote(text: report.notes, icon: "text.bubble") }
                if !report.denials.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        QSLabel("Not allowed, so not done", icon: "hand.raised")
                        ForEach(report.denials, id: \.self) { Text($0).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary) }
                    }
                }
                if let seconds = report.seconds {
                    Text("Agent: \(Int(seconds)) s" + (report.cost.map { String(format: ", about %.2f USD", $0) } ?? ""))
                        .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .padding(Theme.Space.xl)
        }
        .frame(width: Theme.Size.sheetWidth)
        .frame(maxHeight: Theme.Size.sheetMaxHeight)
        .background(QSWindowBackground())
    }
}

/// One of his issues whose due date has passed: how late it is, how many times it was pushed, and what it is about.
struct ExpiredCardView: View {
    let item: ExpiredItem

    var body: some View {
        let i = item.issue
        QSDeckCard {
            HStack(spacing: Theme.Space.s) {
                QSTag(text: item.daysLate == 1 ? "1 day late" : "\(item.daysLate) days late", icon: Theme.Icon.due, color: Theme.Palette.prFailing)
                Text(i.identifier).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                Text(i.state.name).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                QSOpenLinkButton(url: URL(string: i.url), help: "Open \(i.identifier) in Linear")
            }
            Text(i.title).font(Theme.Text.heroTitle).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Space.m) {
                if let due = i.dueDate { Label("Was due " + QSDate.friendly(due), systemImage: Theme.Icon.due) }
                Label(i.priorityName.capitalized, systemImage: "flag")
                if let p = i.project?.name { Label(p, systemImage: "folder") }
            }
            .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
            if item.postpones > 0 {
                QSNote(text: item.canPostpone
                       ? "Postponed \(item.postpones) of \(ExpiredItem.maxPostpones) times."
                       : "Postponed \(item.postpones) times. No more new dates: do it today, send it to the backlog, cancel it or close it.",
                       icon: "clock.arrow.circlepath", warning: !item.canPostpone)
            }
            if !item.description.isEmpty {
                MarkdownBlock(item.description).font(Theme.Text.body)
            }
        }
    }
}

/// An item the auditor filed: what it will do, why, and where it came from.
struct TriageCardView: View {
    let item: TriageItem

    var body: some View {
        QSDeckCard {
            HStack(spacing: Theme.Space.s) {
                QSTag(text: "Triage", icon: Theme.Icon.inbox, color: Theme.Palette.accent)
                Text(item.id).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                if let created = item.created {
                    Text(QSDate.ago(created)).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer()
                QSOpenLinkButton(url: item.url, help: "Open \(item.id) in Linear")
            }
            Text(item.title).font(Theme.Text.heroTitle).fixedSize(horizontal: false, vertical: true)

            if !item.intro.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(Array(item.intro.enumerated()), id: \.offset) { _, line in MD(line).font(Theme.Text.body) }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                QSLabel("Will do", icon: "list.bullet")
                QSBulletList(lines: item.willDo)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.well))

            if !item.why.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    QSLabel("Why", icon: "questionmark.circle")
                    QSBulletList(lines: item.why, secondary: true)
                }
            }

            ForEach(item.others, id: \.self) { section in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    QSLabel(section.title, icon: section.title.lowercased() == "qa" ? Theme.Icon.qa : "text.alignleft")
                    MarkdownBlock(section.body).font(Theme.Text.body)
                }
            }

            if let source = item.source, !source.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Image(systemName: "link").foregroundStyle(Theme.Palette.textTertiary)
                    MD("**Source:** " + source).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
    }
}

/// A pull request the auditor opened on the vault: what changes, and how much.
struct PullRequestCardView: View {
    let pr: VaultPullRequest
    private let maxFiles = 6

    var body: some View {
        QSDeckCard {
            HStack(spacing: Theme.Space.s) {
                QSTag(text: "Vault PR", icon: Theme.Icon.pullRequest, color: Theme.Palette.prOpen)
                Text("#\(pr.number)").font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                if let created = pr.created {
                    Text(QSDate.ago(created)).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer()
                QSOpenLinkButton(url: pr.url, help: "Open #\(pr.number) on GitHub")
            }
            Text(pr.title).font(Theme.Text.heroTitle).fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Space.m) {
                Text("+\(pr.additions)").foregroundStyle(Theme.Palette.prOpen)
                Text("−\(pr.deletions)").foregroundStyle(Theme.Palette.prFailing)
                Text("\(pr.files.count) \(pr.files.count == 1 ? "file" : "files")").foregroundStyle(Theme.Palette.textSecondary)
            }
            .font(Theme.Text.number)

            let changes = pr.changes
            if !changes.isEmpty || !pr.summary.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    QSLabel("What changes", icon: "list.bullet")
                    if changes.isEmpty { MD(pr.summary).font(Theme.Text.body) } else { QSBulletList(lines: changes) }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.well))
            }

            if !pr.files.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    QSLabel("Files", icon: "doc.text")
                    ForEach(pr.files.prefix(maxFiles), id: \.self) { path in
                        Text(path).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                    }
                    if pr.files.count > maxFiles {
                        Text("and \(pr.files.count - maxFiles) more").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
        }
    }
}
