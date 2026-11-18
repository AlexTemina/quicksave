import SwiftUI

/// The On-call tab: the button that reviews the board, the review to correct and apply, the Slack calls, and the
/// on-call board in three bands. See docs/oncall.md.
struct OnCallView: View {
    @ObservedObject var store: Store
    @State private var confirming = false
    @State private var showRest = false
    @State private var showSeenCalls = false

    private var review: OnCallReview? { store.onCall.review }
    private var pending: [OnCallProposal] {
        (review?.items ?? []).filter { $0.open && !($0.issue.map { store.onCallOthers.contains($0) } ?? false) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header
                if let n = store.onCallNotice {
                    HStack(alignment: .firstTextBaseline) {
                        QSNote(text: n, icon: "exclamationmark.triangle", warning: true)
                        QSIconButton(systemImage: "xmark", help: "Hide this message") { store.onCallNotice = nil }
                    }
                }
                if let n = store.moveNotice { QSNote(text: n, icon: "exclamationmark.triangle", warning: true) }
                if store.onCallBusy && pending.isEmpty { working }
                if !store.onCallUnfinished.isEmpty && pending.isEmpty { unfinished }
                if let r = review, !pending.isEmpty { reviewSection(r) }
                else if let r = review, r.appliedAt != nil, !r.items.isEmpty { appliedLine(r) }
                slackCalls
                board
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(QSWindowBackground().ignoresSafeArea())
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                Text("On-call").font(Theme.Text.pageTitle)
                Text(shiftText).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                if let last = store.onCall.lastReview {
                    Text("Last review \(QSDate.ago(last))").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                }
                QSIconButton(systemImage: "arrow.clockwise", help: "Read Linear again", enabled: !store.loading) { Task { await store.refresh() } }
                QSPrimaryButton(title: "Review on-call", icon: "list.bullet.clipboard", busy: store.onCallBusy && pending.isEmpty,
                                enabled: !store.onCallBusy) { Task { await store.reviewOnCall() } }
                    .help("An agent reads the on-call board and the Slack calls and proposes what to do with each card. Nothing is written until you apply.")
            }
            if let q = store.onCallQuest {
                HStack(spacing: Theme.Space.s) {
                    QSLabel("On-call Quest", icon: "light.beacon.max.fill", accent: true)
                    Text(q.title).font(Theme.Text.body)
                    QSOpenLinkButton(url: q.url ?? URL(string: "https://linear.app/alan-eu/issue/\(q.identifier)"), help: "Open \(q.identifier) in Linear")
                }
            }
        }
    }

    private var shiftText: String {
        let run = OnCall.shiftRun(store.onCall.shiftDays)
        if let last = run.last { return run.count == 1 ? "On shift today" : "On shift until \(OnCall.shortDay(last))" }
        return store.onCall.shiftChecked == Morning.today ? "Not on shift today" : "Reading your shift from Alan Home…"
    }

    private var working: some View {
        HStack(spacing: Theme.Space.s) {
            ProgressView().controlSize(.small)
            Text((store.onCallStep ?? "Working") + "…").font(Theme.Text.body)
            Spacer()
        }
        .padding(Theme.Space.l)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.raised))
    }

    /// Apply was cut short: cards that entered are not on the board or have no agent. Finishing writes nothing new to
    /// those issues: it only puts them on the on-call Main Quest and starts their agents.
    private var unfinished: some View {
        let ids = store.onCallUnfinished
        return HStack(spacing: Theme.Space.m) {
            QSNote(text: "\(ids.count) card\(ids.count == 1 ? "" : "s") entered but \(ids.count == 1 ? "is" : "are") not on your board yet: " + ids.joined(separator: ", ")
                   + ". Finish puts them on the on-call Main Quest. It changes nothing else in those issues.",
                   icon: "exclamationmark.triangle", warning: true)
            Spacer()
            QSPrimaryButton(title: "Finish Apply", icon: "checkmark.circle.fill", busy: store.onCallBusy, enabled: !store.onCallBusy) {
                Task { await store.applyOnCall() }
            }
        }
        .padding(Theme.Space.l)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.raised))
    }

    private func appliedLine(_ r: OnCallReview) -> some View {
        let failed = r.items.filter { $0.applyError != nil }
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            QSNote(text: "Review applied \(QSDate.ago(r.appliedAt ?? r.created)): \(r.items.filter(\.enters).count) entered your on-call board.",
                   icon: Theme.Icon.published)
            if !failed.isEmpty {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        ForEach(failed) { f in QSNote(text: "\(f.issue ?? f.tag): \(f.applyError ?? "")", icon: "exclamationmark.triangle", warning: true) }
                    }
                    QSIconButton(systemImage: "xmark", help: "Hide these messages") {
                        store.editOnCall { s in
                            guard var items = s.review?.items else { return }
                            for i in items.indices { items[i].applyError = nil }
                            s.review?.items = items
                        }
                    }
                }
            }
        }
    }

    // MARK: The review

    private func reviewSection(_ r: OnCallReview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack {
                QSLabel("Review · \(pending.count) card\(pending.count == 1 ? "" : "s")", icon: "list.bullet.clipboard")
                Spacer()
                Text("Proposed \(QSDate.ago(r.created))").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary)
            }
            if !r.summary.isEmpty { MarkdownBlock(r.summary).font(Theme.Text.body) }
            let groups = store.onCall.groups
            let grouped = Dictionary(grouping: pending.filter { $0.currentParent.map { groups[$0] != nil } ?? false }, by: { $0.currentParent! })
            let singles = pending.filter { !($0.currentParent.map { groups[$0] != nil } ?? false) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: Theme.Space.m, alignment: .top)], spacing: Theme.Space.m) {
                ForEach(grouped.keys.sorted(), id: \.self) { g in groupCard(g, name: groups[g] ?? g, grouped[g] ?? []) }
                ForEach(singles) { proposalCard($0) }
            }
            QSConversation(
                purpose: "Talk the review through with the agent that made it. It applies what you say and the corrections you wrote on the cards. Nothing reaches Linear until you apply.",
                turns: r.chat.flatMap { t -> [QSConversationTurn] in
                    if t.mine { return [QSConversationTurn(id: t.id * 2, who: .me, text: t.text)] }
                    var out = [QSConversationTurn(id: t.id * 2, who: .ai, text: t.text)]
                    if let c = t.changed { out.append(QSConversationTurn(id: t.id * 2 + 1, who: .event, text: "Changed: " + c)) }
                    return out
                },
                busy: store.onCallBusy,
                step: store.onCallStep,
                quick: pending.contains { !$0.correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ? ["Apply my corrections on the cards"] : [],
                placeholder: "Say what to change, or ask about a card",
                send: { msg in Task { await store.talkOnCall(msg) } }
            ) { _ in EmptyView() }
            applyBar
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.raised))
    }

    private func proposalCard(_ p: OnCallProposal) -> some View {
        let busy = store.onCallBusy
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Text(p.issue ?? "Slack").font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                if p.issue == nil { QSTag(text: "No issue yet", icon: "bubble.left", color: Theme.Palette.agentAsking) }
                if p.touched { QSTag(text: "Changed by the agent", icon: Theme.Icon.agentLive, color: Theme.Palette.touched) }
                Spacer()
                if let g = p.currentParent {
                    let title = store.onCall.parentTitles[g]
                    Button { store.setGroup(g, name: title ?? groupName(p)) } label: {
                        Label("Group under \(g)" + (title.map { " (\($0))" } ?? ""), systemImage: "rectangle.stack").lineLimit(1)
                    }
                    .buttonStyle(QSHoverStyle()).font(Theme.Text.micro).foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: 260, alignment: .trailing)
                    .linkPreview(URL(string: "https://linear.app/alan-eu/issue/\(g)"))
                    .help("Its parent: \(g)\(title.map { " " + $0 } ?? ""). Groups every card under it into one, from now on. Undo it on the group card.")
                }
                if let s = p.slackLink.flatMap(URL.init) { QSOpenLinkButton(url: s, help: "Open the Slack message") }
                if let u = p.url.flatMap(URL.init) { QSOpenLinkButton(url: u, help: "Open in Linear") }
            }
            Text(p.tag.isEmpty ? p.title : p.tag).font(Theme.Text.cardTitle)
            if !p.tag.isEmpty { Text(p.title).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2) }
            HStack(spacing: Theme.Space.m) {
                Menu {
                    ForEach(OnCall.priorities, id: \.self) { pr in
                        Button(pr.capitalized) { store.editProposal(p.id) { $0.priority = pr; $0.touched = false } }
                    }
                } label: { priorityPill(p.priority) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(busy)
                    .help("Priority to set in Linear")
                if p.priority != p.currentPriority && p.issue != nil {
                    Text("was \(p.currentPriority)").font(Theme.Text.micro).foregroundStyle(Theme.Palette.textTertiary)
                }
                Text(p.state == p.currentState || p.currentState.isEmpty ? p.state : "\(p.currentState) → \(p.state)")
                    .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                Toggle("Enters today", isOn: Binding(get: { p.enters }, set: { v in store.editProposal(p.id) { $0.enters = v; $0.touched = false } }))
                    .toggleStyle(.switch).controlSize(.small).font(Theme.Text.meta).disabled(busy)
            }
            let extra = [p.parent.map { "parent \($0)" }, p.typeLabel.map { "label \($0)" }, p.assignToMe ? "assign to you" : nil].compactMap { $0 }
            if !extra.isEmpty { Text(extra.joined(separator: " · ")).font(Theme.Text.micro).foregroundStyle(Theme.Palette.textTertiary) }
            MD(p.why).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
            QSTextArea(text: Binding(get: { p.correction }, set: { v in store.editProposal(p.id) { $0.correction = v } }),
                       placeholder: "Correction for this card", enabled: !busy, minLines: 3, maxLines: 10)
                .padding(Theme.Space.s)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.xs).fill(Theme.Palette.well))
        }
        .padding(Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
            .strokeBorder(p.enters ? priorityColor(p.priority).opacity(0.7) : Theme.Palette.hairline, lineWidth: p.enters ? 1.2 : 0.5))
        .opacity(p.enters || p.changesLinear ? 1 : 0.7)
    }

    /// A short name for a group, from what its first card says it is.
    private func groupName(_ p: OnCallProposal) -> String {
        let words = p.tag.split(separator: " ").prefix(3).joined(separator: " ")
        return words.isEmpty ? (p.currentParent ?? "group") : words
    }

    /// Every pending card under a parent he grouped, as one card. What he sets here applies to all of them.
    private func groupCard(_ parent: String, name: String, _ items: [OnCallProposal]) -> some View {
        let busy = store.onCallBusy
        let counts = OnCall.priorities.compactMap { pr -> String? in
            let n = items.filter { $0.priority == pr }.count
            return n == 0 ? nil : "\(n) \(pr)"
        }
        let worst = OnCall.priorities.first { pr in items.contains { $0.priority == pr } } ?? "none"
        let enters = items.contains(where: \.enters)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Text(parent).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                    .linkPreview(URL(string: "https://linear.app/alan-eu/issue/\(parent)"))
                QSTag(text: "Group · \(items.count)", icon: "rectangle.stack.fill", color: Theme.Palette.accent)
                Spacer()
                Button { store.setGroup(parent, name: nil) } label: { Label("Ungroup", systemImage: "rectangle.stack.badge.minus") }
                    .buttonStyle(QSHoverStyle()).font(Theme.Text.micro).foregroundStyle(Theme.Palette.textSecondary)
                    .help("Show these cards one by one again")
                if let u = URL(string: "https://linear.app/alan-eu/issue/\(parent)") { QSOpenLinkButton(url: u, help: "Open the parent in Linear") }
            }
            Text(store.onCall.parentTitles[parent] ?? name).font(Theme.Text.cardTitle)
            Text(counts.joined(separator: " · ")).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: Theme.Space.m) {
                Menu {
                    ForEach(OnCall.priorities, id: \.self) { pr in
                        Button("All to \(pr)") { store.editGroup(parent) { $0.priority = pr; $0.touched = false } }
                    }
                    Button("Keep each as proposed") {}
                } label: { priorityPill(worst) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(busy)
                    .help("Set the priority of every card in the group")
                Spacer()
                Toggle("Enters today", isOn: Binding(get: { enters }, set: { v in store.editGroup(parent) { $0.enters = v; $0.touched = false } }))
                    .toggleStyle(.switch).controlSize(.small).font(Theme.Text.meta).disabled(busy)
                    .help("The group enters as one card, its parent, with one agent for all of it")
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items.prefix(5)) { c in
                    Text("\(c.issue ?? "") \(c.title)").font(Theme.Text.micro).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                }
                if items.count > 5 { Text("and \(items.count - 5) more").font(Theme.Text.micro).foregroundStyle(Theme.Palette.textTertiary) }
            }
            QSTextArea(text: Binding(get: { items.first?.correction ?? "" }, set: { v in store.editGroup(parent) { $0.correction = v } }),
                       placeholder: "Correction for the whole group", enabled: !busy, minLines: 3, maxLines: 10)
                .padding(Theme.Space.s)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.xs).fill(Theme.Palette.well))
        }
        .padding(Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
            .strokeBorder(enters ? priorityColor(worst).opacity(0.7) : Theme.Palette.hairline, lineWidth: enters ? 1.2 : 0.5))
    }

    private func priorityPill(_ p: String) -> some View {
        QSTag(text: p.capitalized, icon: p == "urgent" ? "exclamationmark.3" : p == "high" ? "exclamationmark.2" : "minus", color: priorityColor(p))
    }

    private func priorityColor(_ p: String) -> Color {
        switch p {
        case "urgent": return Theme.Palette.prFailing
        case "high": return Theme.Palette.warning
        default: return Theme.Palette.textSecondary
        }
    }

    private var applyBar: some View {
        let writes = pending.filter(\.changesLinear).count
        let enter = pending.filter(\.enters).count
        let what = [writes > 0 ? "\(writes) to Linear" : nil, enter > 0 ? "\(enter) enter\(enter == 1 ? "s" : "")" : nil].compactMap { $0 }
        return HStack {
            QSNote(text: "Apply writes priority, state, owner, parent and type to Linear and puts the entering cards on your on-call board. Start on a card opens its worktree and agent.")
            Spacer()
            QSPrimaryButton(title: what.isEmpty ? "Apply" : "Apply: " + what.joined(separator: ", "), icon: "checkmark.circle.fill",
                            busy: store.onCallBusy && store.onCallStep?.hasPrefix("Writing") == true,
                            enabled: !store.onCallBusy && !pending.isEmpty) { confirming = true }
        }
        .confirmationDialog("Apply this review?", isPresented: $confirming) {
            Button("Apply") { Task { await store.applyOnCall() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It writes \(writes) change\(writes == 1 ? "" : "s") to Linear and puts \(enter) card\(enter == 1 ? "" : "s") on your on-call board.")
        }
    }

    // MARK: Slack

    @ViewBuilder private var slackCalls: some View {
        let seen = Set(store.onCall.seenCalls)
        let all = store.onCall.slackCalls
        let calls = all.filter { showSeenCalls || !seen.contains($0.id) }
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.m) {
                    QSLabel("Calls in Slack today · \(all.count - seen.count) unread", icon: "bubble.left.and.bubble.right")
                    Spacer()
                    if !seen.isEmpty {
                        Button(showSeenCalls ? "Hide read" : "Show \(seen.count) read") { showSeenCalls.toggle() }
                            .buttonStyle(QSHoverStyle()).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    if all.count > seen.count {
                        Button("Mark all read") { store.editOnCall { $0.seenCalls = all.map(\.id) } }
                            .buttonStyle(QSHoverStyle()).font(Theme.Text.meta).foregroundStyle(Theme.Palette.accent)
                    }
                }
                ForEach(calls.reversed()) { c in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        QSTag(text: "@" + c.handle, icon: "at", color: c.handle.contains("spain") ? Theme.Palette.prFailing : Theme.Palette.textSecondary)
                        Text("#\(c.channel) · \(c.author)").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                        Text(c.text).font(Theme.Text.body).lineLimit(2)
                        Spacer(minLength: 0)
                        if let i = c.issue { Text(i).font(Theme.Text.code).foregroundStyle(Theme.Palette.textTertiary) }
                        if let u = URL(string: c.link) { QSOpenLinkButton(url: u, help: "Open in Slack") }
                        let read = seen.contains(c.id)
                        QSIconButton(systemImage: read ? "envelope.badge" : "checkmark.circle", help: read ? "Mark as unread" : "Mark as read") {
                            store.editOnCall { s in if read { s.seenCalls.removeAll { $0 == c.id } } else { s.seenCalls.append(c.id) } }
                        }
                    }
                    .opacity(seen.contains(c.id) ? 0.5 : 1)
                }
            }
        }
    }

    // MARK: The board

    @ViewBuilder private var board: some View {
        let cards = store.onCallCards
        if cards.isEmpty {
            if review == nil && !store.onCallBusy {
                QSEmptyState(icon: "light.beacon.max", title: "Nothing on your on-call board yet",
                             subtitle: "Review on-call reads the board and Slack and proposes what enters today.")
            }
        } else {
            band("Urgent", "now", cards.filter { $0.priority == "urgent" }, color: Theme.Palette.prFailing)
            band("High", "today", cards.filter { $0.priority == "high" }, color: Theme.Palette.warning)
            let rest = cards.filter { $0.priority != "urgent" && $0.priority != "high" }
            if !rest.isEmpty {
                Button { showRest.toggle() } label: {
                    Label("The rest · \(rest.count)", systemImage: showRest ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(QSHoverStyle(padding: 2)).font(Theme.Text.label).foregroundStyle(Theme.Palette.textSecondary)
                if showRest || rest.contains(where: { store.focusCard == $0.id }) {
                    StateBoard(store: store, items: rest) { PieceCard(piece: $0, store: store) }
                }
            }
        }
    }

    @ViewBuilder private func band(_ title: String, _ when: String, _ items: [Piece], color: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.s) {
                    QSDot(color: color)
                    Text("\(title) · \(when)").font(Theme.Text.label)
                    Text("\(items.filter { $0.column == .done }.count) of \(items.count) done").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                }
                StateBoard(store: store, items: items) { PieceCard(piece: $0, store: store) }
            }
        }
    }
}

/// On Today, above the usual Main Quest during a shift: the on-call Main Quest, its counts, and the way to the tab.
struct OnCallQuestCard: View {
    let quest: OnCall.Quest
    @ObservedObject var store: Store

    var body: some View {
        let open = store.onCallCards.filter { $0.column != .done }
        let urgent = open.filter { $0.priority == "urgent" }.count
        let high = open.filter { $0.priority == "high" }.count
        QSHeroCard {
            HStack(spacing: Theme.Space.s) {
                QSLabel("On-call Quest", icon: "light.beacon.max.fill", accent: true)
                Spacer()
                QSOpenLinkButton(url: quest.url ?? URL(string: "https://linear.app/alan-eu/issue/\(quest.identifier)"), help: "Open \(quest.identifier) in Linear")
            }
            Text(quest.title).font(Theme.Text.heroTitle)
            HStack(spacing: Theme.Space.m) {
                QSProgress(segments: store.onCallCards.map { (store.color(of: $0.stateName, fallback: $0.column.fallbackHex), $0.column == .done) })
                    .frame(maxWidth: 260)
                Text("\(urgent) urgent · \(high) high · \(open.count - urgent - high) other open")
                    .font(Theme.Text.number).foregroundStyle(Theme.Palette.textSecondary)
                if let last = store.onCall.lastReview {
                    Text("last review \(QSDate.ago(last))").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer()
                Button { store.tab = .oncall } label: { Label("Open on-call", systemImage: "arrow.right.circle") }
                    .buttonStyle(QSHoverStyle())
            }
        }
    }
}
