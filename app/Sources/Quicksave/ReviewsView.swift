import SwiftUI

/// Pull requests waiting for his review on the left, the review of the one he picked on the right. See docs/reviews.md.
struct ReviewsView: View {
    @ObservedObject var store: Store

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: Theme.Size.reviewListWidth)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(QSWindowBackground())
        .task { if store.reviewRequests.isEmpty { await store.refreshReviews() } }
    }

    // MARK: List

    /// Reviews where something happened on GitHub that he has not seen: they go first.
    private var active: [PRReview] {
        store.reviews.values.filter { !$0.unseenActivity.isEmpty }.sorted { $0.number < $1.number }
    }
    private var activeIds: Set<Int> { Set(active.map(\.number)) }
    private var mine: [ReviewRequest] { store.reviewRequests.filter { !$0.shared && !activeIds.contains($0.number) } }
    private var shared: [ReviewRequest] { store.reviewRequests.filter { $0.shared && !activeIds.contains($0.number) } }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    Text("Reviews").font(Theme.Text.pageTitle)
                    Spacer()
                    QSIconButton(systemImage: "arrow.clockwise", help: "Read GitHub again") { Task { await store.refreshReviews() } }
                }
                if let e = store.reviewsError { QSNote(text: e, icon: "exclamationmark.triangle", warning: true) }
                if store.reviewRequests.isEmpty && store.reviewedOnly.isEmpty {
                    QSEmptyState(icon: Theme.Icon.review, title: "Nothing to review", subtitle: "No pull request asks for you by name.")
                }
                group("New activity", active.map(Row.reviewed))
                group("Asked of you", mine.map(Row.request))
                group("Many reviewers", shared.map(Row.request))
                group("Reviewed, still open", store.reviewedOnly.filter { !activeIds.contains($0.number) }.map(Row.reviewed))
            }
            .padding(Theme.Space.l)
        }
    }

    private enum Row: Identifiable {
        case request(ReviewRequest), reviewed(PRReview)
        var id: Int { switch self { case .request(let r): return r.number; case .reviewed(let r): return r.number } }
    }

    @ViewBuilder private func group(_ title: String, _ rows: [Row]) -> some View {
        if !rows.isEmpty {
            QSLabel("\(title) · \(rows.count)").padding(.top, Theme.Space.m)
            ForEach(rows) { row in
                Button { store.reviewOpen = row.id } label: { rowView(row) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func rowView(_ row: Row) -> some View {
        let n = row.id
        let review = store.reviews[n]
        return QSCard(highlighted: store.reviewOpen == n, tint: tint(n), pulsing: store.reviewBusy.contains(n)) {
            switch row {
            case .request(let pr):
                Text(pr.title).font(Theme.Text.cardTitle).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: Theme.Space.s) {
                    Text("#\(pr.number)").font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                    Text(pr.author).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                    Spacer(minLength: 0)
                    sizeText(pr.additions, pr.deletions)
                }
                HStack(spacing: Theme.Space.s) {
                    if let c = pr.created { Text(QSDate.ago(c)).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary) }
                    Text(pr.reviewers == 1 ? "only you" : "\(pr.reviewers) reviewers")
                        .font(Theme.Text.meta).foregroundStyle(pr.shared ? Theme.Palette.textTertiary : Theme.Palette.textSecondary)
                    if pr.isDraft { QSPill(text: "Draft", color: Theme.Palette.prDraft) }
                    Spacer(minLength: 0)
                    stateTag(n, review)
                }
            case .reviewed(let r):
                Text(r.title).font(Theme.Text.cardTitle).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: Theme.Space.s) {
                    Text("#\(r.number)").font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                    Text(r.author).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                    Spacer(minLength: 0)
                    stateTag(n, r)
                }
            }
            if let r = review, !r.unseenActivity.isEmpty {
                HStack(spacing: Theme.Space.s) {
                    if r.newReplies > 0 {
                        QSTag(text: r.newReplies == 1 ? "1 new reply" : "\(r.newReplies) new replies", icon: "bubble.left.fill", color: Theme.Palette.agentAsking)
                    }
                    if r.unseenActivity.contains(where: { $0.hasPrefix("h") }) {
                        QSTag(text: r.newCommits == 1 ? "1 new commit" : "\(r.newCommits) new commits", icon: "arrow.triangle.branch", color: Theme.Palette.agentAsking)
                    }
                }
            }
        }
    }

    private func tint(_ n: Int) -> Color? {
        if store.reviewBusy.contains(n) { return Theme.Palette.agentWorking }
        return nil
    }

    @ViewBuilder private func stateTag(_ n: Int, _ r: PRReview?) -> some View {
        if store.reviewBusy.contains(n) {
            QSTag(text: store.reviewSteps[n] ?? "Working", icon: Theme.Icon.agentLive, color: Theme.Palette.agentWorking)
        } else if let r {
            switch r.state {
            case .failed: QSTag(text: "Failed", icon: "exclamationmark.triangle", color: Theme.Palette.prFailing)
            case .preparing: QSTag(text: "Preparing", icon: Theme.Icon.agentLive, color: Theme.Palette.agentWorking)
            case .ready:
                if r.everPublished && !r.hasPending {
                    QSTag(text: "Published", icon: Theme.Icon.published, color: Theme.Palette.published)
                } else {
                    QSTag(text: "Ready", icon: "checkmark", color: Theme.Palette.accent)
                }
            }
        }
    }

    private func sizeText(_ add: Int, _ del: Int) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Text("+\(add)").foregroundStyle(Theme.Palette.prOpen)
            Text("−\(del)").foregroundStyle(Theme.Palette.prFailing)
        }
        .font(Theme.Text.code)
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let n = store.reviewOpen, let pr = store.reviewRequests.first(where: { $0.number == n }) ?? store.reviews[n].map(Self.request) {
            ReviewDetail(store: store, pr: pr).id(n)
        } else {
            QSEmptyState(icon: Theme.Icon.review, title: "Pick a pull request",
                         subtitle: "Start review prepares the context, a first pass of comments, the flow and a worktree.")
        }
    }

    /// A pull request no longer requested, rebuilt from its review.
    private static func request(_ r: PRReview) -> ReviewRequest {
        ReviewRequest(number: r.number, title: r.title, url: URL(string: r.url) ?? URL(string: "https://github.com")!, author: r.author,
                      created: nil, additions: 0, deletions: 0, changedFiles: 0, reviewers: 0, headRef: r.headRef, baseRef: r.baseRef,
                      isDraft: false)
    }
}

private struct ReviewDetail: View {
    @ObservedObject var store: Store
    let pr: ReviewRequest
    @State private var confirming = false
    /// Activity that was new when he opened it: still highlighted while he is here, already marked seen.
    @State private var fresh: Set<String> = []

    private var review: PRReview? { store.reviews[pr.number] }
    private var busy: Bool { store.reviewBusy.contains(pr.number) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header
                if let r = review, r.state == .ready {
                    ready(r)
                } else {
                    start
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: see)
        .onChange(of: review?.activity ?? []) { see() }
    }

    private func see() {
        guard let r = review else { return }
        fresh.formUnion(r.unseenActivity)
        store.markActivitySeen(pr.number)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(pr.title).font(Theme.Text.heroTitle).textSelection(.enabled)
                QSOpenLinkButton(url: pr.url, help: "Open on GitHub")
            }
            HStack(spacing: Theme.Space.m) {
                Text("#\(pr.number)").font(Theme.Text.code)
                Text("by \(pr.author)").font(Theme.Text.meta)
                if pr.changedFiles > 0 {
                    Text("+\(pr.additions) −\(pr.deletions) · \(pr.changedFiles) files").font(Theme.Text.code)
                }
                if pr.reviewers > 0 { Text(pr.reviewers == 1 ? "only you" : "\(pr.reviewers) reviewers").font(Theme.Text.meta) }
                Text("\(pr.headRef) → \(pr.baseRef)").font(Theme.Text.code).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button {
                    if let w = review?.worktree { Reviews.openInCode(w) }
                } label: { Label("Open in VS Code", systemImage: "chevron.left.forwardslash.chevron.right") }
                    .buttonStyle(QSHoverStyle())
                    .disabled(review?.worktree.map { FileManager.default.fileExists(atPath: $0) } != true)
                    .help("Opens the review worktree with the Review profile")
            }
            .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    // MARK: Not ready

    private var start: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if busy {
                HStack(spacing: Theme.Space.s) {
                    ProgressView().controlSize(.small)
                    Text((store.reviewSteps[pr.number] ?? "Working") + "…").font(Theme.Text.body)
                }
                QSNote(text: "Opens the worktree, gathers the context, runs the first pass and builds the flow. It usually takes a few minutes.")
            } else {
                if let r = review, r.state == .failed {
                    QSNote(text: r.error ?? "The preparation failed.", icon: "exclamationmark.triangle", warning: true)
                }
                QSPrimaryButton(title: review?.state == .failed ? "Try again" : "Start review", icon: Theme.Icon.review) {
                    Task { await store.startReview(pr) }
                }
                QSNote(text: "An agent opens a worktree, gathers the context (Linear, Slack, Notion, the vault), proposes comments and a verdict, and draws the flow. Nothing is posted.")
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.raised))
    }

    // MARK: Ready

    @ViewBuilder private func ready(_ r: PRReview) -> some View {
        section("Context") {
            MarkdownBlock(r.context).textSelection(.enabled)
        }
        if let page = r.flowPage {
            section("Flow", trailing: {
                QSIconButton(systemImage: "safari", help: "Open in the browser") { NSWorkspace.shared.open(URL(fileURLWithPath: page)) }
            }) {
                QSWebPage(file: URL(fileURLWithPath: page))
                    .frame(height: Theme.Size.flowHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
            }
        }
        if r.newCommits > 0 || r.recheck != nil { commits(r) }
        if let talk = r.conversation, !talk.isEmpty {
            section("Conversation") {
                ForEach(talk) { post($0, new: fresh.contains("c\($0.id)")) }
            }
        }
        section("Review") {
            verdict(r)
            mainComment(r)
            comments(r)
        }
        section("Your notes") { notes(r) }
        publishBar(r)
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        section(title, trailing: { EmptyView() }, content: content)
    }

    private func section<T: View, C: View>(_ title: String, @ViewBuilder trailing: () -> T, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack { QSLabel(title); Spacer(); trailing() }
            content()
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.raised))
    }

    private func verdict(_ r: PRReview) -> some View {
        HStack(spacing: Theme.Space.m) {
            Text("Verdict").font(Theme.Text.body).foregroundStyle(Theme.Palette.textSecondary)
            Picker("", selection: Binding(get: { r.verdict }, set: { v in store.editReview(pr.number) { $0.verdict = v } })) {
                ForEach(ReviewVerdict.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .disabled(busy)
            if let p = r.verdictPublished { publishedTag("Published: \(p.title)") }
            Spacer()
        }
    }

    private func mainComment(_ r: PRReview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("Main comment").font(Theme.Text.body).foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                if r.bodyPublished != nil { publishedTag("Published") } else if r.everPublished { notPublishedTag }
            }
            editor(Binding(get: { r.body }, set: { v in store.editReview(pr.number) { $0.body = v } }),
                   locked: r.bodyPublished != nil || busy)
            if r.bodyPublished == nil {
                Text("The link to the emoji legend is added under it when you publish.")
                    .font(Theme.Text.micro).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    private func comments(_ r: PRReview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Comments · \(r.comments.filter { !$0.dropped }.count)").font(Theme.Text.body).foregroundStyle(Theme.Palette.textSecondary)
            if r.comments.isEmpty { QSNote(text: "No comments yet. Dictate them in your notes.") }
            ForEach(r.comments) { c in commentRow(r, c) }
        }
    }

    private func commentRow(_ r: PRReview, _ c: ReviewComment) -> some View {
        let locked = c.published != nil || busy
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Menu {
                    ForEach(Reviews.emojis, id: \.emoji) { e in
                        Button("\(e.emoji)  \(e.name)") { edit(c.id) { $0.emoji = e.emoji } }
                    }
                } label: { Text(c.emoji).font(.system(size: 18)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .disabled(locked || c.dropped)
                    .help(Reviews.emojis.first { $0.emoji == c.emoji }?.name ?? "Kind of comment")
                Button { if let w = r.worktree { Reviews.openInCode(w, file: c.path, line: c.line) } } label: {
                    Text("\(c.path):\(c.line)").font(Theme.Text.code).lineLimit(1).truncationMode(.head)
                }
                .buttonStyle(QSHoverStyle()).foregroundStyle(Theme.Palette.link)
                .help("Open this line in VS Code")
                Spacer()
                if c.published != nil { publishedTag("Published") }
                else {
                    if c.touched { QSTag(text: "Changed by your notes", icon: Theme.Icon.agentLive, color: Theme.Palette.touched) }
                    if r.everPublished && !c.dropped { notPublishedTag }
                    QSIconButton(systemImage: c.dropped ? "arrow.uturn.backward" : "trash",
                                 help: c.dropped ? "Keep it" : "Drop it", enabled: !busy) { edit(c.id) { $0.dropped.toggle() } }
                }
            }
            if c.dropped {
                Text(c.text).font(Theme.Text.body).strikethrough().foregroundStyle(Theme.Palette.textTertiary).lineLimit(2)
            } else {
                editor(Binding(get: { c.text }, set: { v in edit(c.id) { $0.text = v } }), locked: locked)
            }
            if let addressed = c.addressed {
                Label(c.status ?? (addressed ? "Addressed" : "Not addressed yet"),
                      systemImage: addressed ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(Theme.Text.meta).foregroundStyle(addressed ? Theme.Palette.published : Theme.Palette.warning)
            }
            if c.published != nil {
                ForEach(c.thread ?? []) { post($0, new: fresh.contains("r\($0.id)")) }
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    Image(systemName: "arrowshape.turn.up.left").foregroundStyle(Theme.Palette.textTertiary).padding(.top, Theme.Space.s)
                    TextField("Reply in this thread", text: Binding(get: { c.reply ?? "" }, set: { v in replyEdit(c.id, v) }), axis: .vertical)
                        .textFieldStyle(.plain).font(Theme.Text.body).lineLimit(1...10).disabled(busy)
                        .padding(Theme.Space.s)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.xs).fill(Theme.Palette.well))
                    if c.pendingReply != nil { notPublishedTag }
                }
            }
        }
        .padding(Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
            .strokeBorder(c.published != nil ? Theme.Palette.published.opacity(0.6) : (c.touched ? Theme.Palette.touched : Theme.Palette.hairline),
                          lineWidth: c.published != nil || c.touched ? 1.2 : 0.5))
        .opacity(c.dropped ? 0.6 : 1)
    }

    private func replyEdit(_ id: String, _ text: String) {
        store.editReview(pr.number) { r in
            if let i = r.comments.firstIndex(where: { $0.id == id }) { r.comments[i].reply = text }
        }
    }

    /// One message on GitHub: who, when, what. New ones are marked.
    private func post(_ p: ThreadPost, new: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                Text(p.mine ? "You" : p.author).font(Theme.Text.label)
                if let d = p.created { Text(QSDate.ago(d)).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary) }
                if new { QSTag(text: "New", icon: "sparkle", color: Theme.Palette.agentAsking) }
            }
            MarkdownBlock(p.body).textSelection(.enabled)
        }
        .padding(Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.xs).fill(new ? Theme.Palette.agentAsking.opacity(0.08) : Theme.Palette.well))
        .padding(.leading, Theme.Space.l)
    }

    /// The author pushed after his review: how many commits, and the button that checks them against his comments.
    private func commits(_ r: PRReview) -> some View {
        section("New commits") {
            HStack(spacing: Theme.Space.m) {
                if r.newCommits > 0 {
                    Text(r.newCommits == 1 ? "1 commit since your review." : "\(r.newCommits) commits since your review.")
                        .font(Theme.Text.body)
                }
                Spacer()
                if busy && store.reviewSteps[pr.number] != "Publishing" {
                    ProgressView().controlSize(.small)
                    Text((store.reviewSteps[pr.number] ?? "Working") + "…").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                } else if r.newCommits > 0 && r.recheckedHead != r.headNow {
                    Button { Task { await store.recheckReview(pr.number) } } label: { Label("Check the new commits", systemImage: Theme.Icon.agentLive) }
                        .buttonStyle(QSHoverStyle()).foregroundStyle(Theme.Palette.accent)
                }
            }
            if let s = r.recheck {
                Label(s, systemImage: "checkmark").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
            }
            QSNote(text: "It updates the worktree, marks which of your comments were dealt with, drafts replies and proposes new comments. Nothing is posted.")
        }
    }

    private func edit(_ id: String, _ change: @escaping (inout ReviewComment) -> Void) {
        store.editReview(pr.number) { r in
            guard let i = r.comments.firstIndex(where: { $0.id == id }), r.comments[i].published == nil else { return }
            change(&r.comments[i])
            r.comments[i].touched = false
        }
    }

    private func editor(_ text: Binding<String>, locked: Bool) -> some View {
        TextField("", text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Theme.Text.body)
            .lineLimit(1...20)
            .disabled(locked)
            .foregroundStyle(locked ? Theme.Palette.textSecondary : Theme.Palette.textPrimary)
            .padding(Theme.Space.s)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.xs).fill(Theme.Palette.well))
    }

    private func publishedTag(_ text: String) -> some View {
        QSTag(text: text, icon: Theme.Icon.published, color: Theme.Palette.published)
    }

    private var notPublishedTag: some View {
        QSTag(text: "Not published", icon: "circle.dashed", color: Theme.Palette.warning)
    }

    // MARK: Notes

    private func notes(_ r: PRReview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Label("Talk through the code here. Apply my notes turns them into comments, changes texts and emojis, the main comment or the verdict. Nothing is posted.",
                  systemImage: Theme.Icon.agentLive)
                .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
            TextEditor(text: Binding(get: { r.notes }, set: { v in store.editReview(pr.number) { $0.notes = v } }))
                .font(Theme.Text.body)
                .scrollContentBackground(.hidden)
                .padding(Theme.Space.s)
                .frame(minHeight: Theme.Size.notesMinHeight)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.well))
                .disabled(busy)
            HStack(spacing: Theme.Space.m) {
                if busy, store.reviewSteps[pr.number] != "Publishing" {
                    ProgressView().controlSize(.small)
                    Text((store.reviewSteps[pr.number] ?? "Working") + "…").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                } else if let change = r.lastChange {
                    Label(change, systemImage: "checkmark").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                Button { Task { await store.applyNotes(pr.number) } } label: { Label("Apply my notes", systemImage: Theme.Icon.agentLive) }
                    .buttonStyle(QSHoverStyle()).foregroundStyle(Theme.Palette.accent)
                    .disabled(busy || r.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: Publish

    private func publishBar(_ r: PRReview) -> some View {
        let event = r.pendingEvent
        let count = r.unpublished.count
        let bodyPending = r.bodyPublished == nil && (!Reviews.withoutLegend(r.body).isEmpty || !r.everPublished)
        let replies = r.pendingReplies.count
        let what = [event.map { r.everPublished && $0 == .comment ? nil : $0.title } ?? nil,
                    event != nil && bodyPending ? "main comment" : nil,
                    count > 0 ? (count == 1 ? "1 comment" : "\(count) comments") : nil,
                    replies > 0 ? (replies == 1 ? "1 reply" : "\(replies) replies") : nil].compactMap { $0 }
        return VStack(alignment: .trailing, spacing: Theme.Space.s) {
            if let notice = store.reviewNotice[pr.number] { QSNote(text: notice, icon: "exclamationmark.triangle", warning: true) }
            HStack {
                if r.everPublished {
                    QSNote(text: !r.hasPending ? "Everything is published." : "Already published items are marked; only the rest goes now.",
                           icon: Theme.Icon.published)
                } else {
                    QSNote(text: "Nothing reaches GitHub until you press Publish.")
                }
                Spacer()
                QSPrimaryButton(title: !r.hasPending ? "Published" : "Publish: " + what.joined(separator: " + "),
                                icon: "paperplane.fill", busy: busy && store.reviewSteps[pr.number] == "Publishing",
                                enabled: r.hasPending && !busy) { confirming = true }
            }
        }
        .confirmationDialog("Publish this review on GitHub?", isPresented: $confirming) {
            Button("Publish") { Task { await store.publishReview(pr.number) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It posts \(what.joined(separator: ", ")) on #\(pr.number). This cannot be undone.")
        }
    }
}
