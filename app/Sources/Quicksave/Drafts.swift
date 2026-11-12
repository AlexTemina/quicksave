import AppKit
import SwiftUI

/// Text Alejandro posts himself somewhere else. Quicksave never posts: it keeps the text, says where it goes, and
/// links to the place. See docs/drafts.md.
struct DraftItem: Identifiable, Hashable {
    let id: Int64
    let place: String
    let note: String
    let link: URL?
    let body: String
    let source: String
    let created: Date
    /// Already left as a draft in Slack itself.
    let drafted: Bool
    /// The code of the item it came from, or empty.
    let item: String
    /// The session of the agent that wrote it, and the folder it ran in, to talk about it with that same agent.
    var session: String? = nil
    var sessionDir: String? = nil
}

/// One turn of the conversation about a draft. A turn with a body is a version of the text.
struct DraftTurn: Identifiable, Hashable {
    enum Who: String { case original, me, agent, hand, back }
    let id: Int64
    let who: Who
    let text: String
    let body: String?
    let created: Date
}

/// A draft as it will look where it goes. Slack has no headings and shows a newline as a newline; everything else
/// (Linear, GitHub, mail) is read as Markdown.
struct DraftPreview: View {
    let text: String
    let place: String

    var body: some View {
        if place == "Slack" { SlackPreview(text: text) } else { MarkdownBlock(text).font(Theme.Text.body) }
    }
}

struct SlackPreview: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(Array(MarkdownBlock.blocks(Self.markdown(from: text)).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let t): MD("**\(t)**").font(Theme.Text.body)
                case .bullet(let mark, let t, let indent):
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(mark == "•" || mark == "☐" || mark == "☑" ? "•" : mark).foregroundStyle(Theme.Palette.textSecondary)
                        MD(t).font(Theme.Text.body)
                    }.padding(.leading, CGFloat(indent) * 14)
                case .code(let t):
                    Text(t).font(Theme.Text.code).textSelection(.enabled)
                        .padding(Theme.Space.s).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.well))
                case .folded(let t): MD(t).font(Theme.Text.body)
                case .paragraph(let t): MD(t).font(Theme.Text.body)
                // Slack shows no tables: each row reads as it was typed.
                case .table(let header, let rows):
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(([header] + rows).enumerated()), id: \.offset) { _, r in Text(r.joined(separator: " | ")).font(Theme.Text.body) }
                    }
                case .quote(let t): MD("> " + t).font(Theme.Text.body)
                case .rule: Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    /// Slack's own link and mention syntax turned into what a person reads.
    static func markdown(from slack: String) -> String {
        var s = slack
        let rules: [(String, String)] = [
            (#"<#C\w+\|([^>]+)>"#, "#$1"),
            (#"<@\w+(?:\|([^>]+))?>"#, "@mention"),
            (#"<(https?://[^|>]+)\|([^>]+)>"#, "[$2]($1)"),
            (#"<(https?://[^>]+)>"#, "$1"),
        ]
        for (pattern, template) in rules {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return s
    }
}

/// Every draft in one place, whichever part of the app produced it. He selects the ones already posted and archives them.
struct DraftsView: View {
    @ObservedObject var store: Store
    @State private var showArchived = false
    @State private var selected: Set<Int64> = []
    @State private var editingId: Int64?
    @State private var editText = ""
    @State private var previewing = false
    /// Drafts whose conversation is open.
    @State private var talking: Set<Int64> = []
    /// Drafts showing what the last version changed.
    @State private var showChanges: Set<Int64> = []

    private var list: [DraftItem] { showArchived ? store.archivedDrafts : store.drafts }

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            header
            if let notice = store.draftsNotice { QSNote(text: notice, icon: "exclamationmark.triangle", warning: true) }
            if list.isEmpty {
                QSEmptyState(icon: "square.and.pencil",
                             title: showArchived ? "Nothing archived" : "No drafts waiting",
                             subtitle: showArchived ? nil : "Text the agents leave for you to post will show up here.")
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Space.m) {
                        ForEach(list) { draft in card(draft) }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            if !selected.isEmpty { selectionBar }
        }
        .frame(maxWidth: Theme.Size.draftsWidth)
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.xl).padding(.bottom, Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QSWindowBackground().ignoresSafeArea())
        .onChange(of: showArchived) { selected = [] }
        .onAppear { store.loadDrafts() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Drafts").font(Theme.Text.pageTitle)
            Spacer()
            Picker("", selection: $showArchived) {
                Text("Open \(store.drafts.count)").tag(false)
                Text("Archived").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 200)
        }
    }

    private var selectionBar: some View {
        HStack(spacing: Theme.Space.m) {
            Text("\(selected.count) selected").font(Theme.Text.number).foregroundStyle(Theme.Palette.textSecondary)
            Button("Clear") { selected = [] }.buttonStyle(QSHoverStyle())
            Spacer()
            QSPrimaryButton(title: showArchived ? "Restore \(selected.count)" : "Archive \(selected.count)",
                            icon: showArchived ? "tray.and.arrow.up" : "archivebox") {
                store.setArchived(Array(selected), !showArchived)
                selected = []
            }
        }
    }

    private static let quick = ["Shorter", "Less jargon", "More direct"]

    /// The versions of a draft, numbered from 1: the first draft, then every rewrite, hand edit or step back.
    private func versions(_ draft: DraftItem) -> [(number: Int, turn: DraftTurn)] {
        (store.draftTurns[draft.id] ?? []).filter { $0.body != nil }.enumerated().map { ($0.offset + 1, $0.element) }
    }

    /// The conversation with the agent about one draft: his messages, its answers, and the versions it left.
    private func thread(_ draft: DraftItem) -> some View {
        let vs = versions(draft)
        let busy = store.talkingIds.contains(draft.id)
        let current = vs.last(where: { $0.turn.body == draft.body })?.number
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            if vs.count > 1 {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(vs, id: \.turn.id) { v in
                        Button("v\(v.number)") { if v.number != current { store.restoreVersion(draft, body: v.turn.body!, number: v.number) } }
                            .buttonStyle(QSHoverStyle())
                            .font(Theme.Text.code)
                            .foregroundStyle(v.number == current ? Theme.Palette.accent : Theme.Palette.textSecondary)
                            .help(v.number == current ? "The text shown now" : "Go back to this version")
                    }
                    Spacer()
                    Toggle("Show changes", isOn: Binding(get: { showChanges.contains(draft.id) },
                                                         set: { if $0 { showChanges.insert(draft.id) } else { showChanges.remove(draft.id) } }))
                        .toggleStyle(.checkbox).font(Theme.Text.meta)
                }
            }
            QSConversation(
                purpose: "Rewrites this draft with you. It may read where the draft came from; nothing leaves Quicksave.",
                turns: conversationTurns(draft),
                busy: busy,
                step: store.talkSteps[draft.id],
                quick: Self.quick,
                placeholder: "Tell it what to change",
                send: { msg in Task { await store.talk(draft, message: msg) } },
                pendingId: store.pendingProposal(draft)?.id,
                acceptTitle: "Use this version",
                accept: { if let p = store.pendingProposal(draft) { store.useProposal(draft, p) } }
            ) { text in DraftPreview(text: text, place: draft.place) }
        }
    }

    /// The draft's conversation in the shared shape: his messages, the agent's notes with the versions it proposed,
    /// its questions, and what happened by hand.
    private func conversationTurns(_ draft: DraftItem) -> [QSConversationTurn] {
        let numbers = Dictionary(uniqueKeysWithValues: versions(draft).map { ($0.turn.id, $0.number) })
        return (store.draftTurns[draft.id] ?? []).compactMap { t in
            switch t.who {
            case .original: return nil
            case .me: return QSConversationTurn(id: t.id, who: .me, text: t.text)
            case .agent:
                guard let body = t.body else { return QSConversationTurn(id: t.id, who: .question, text: t.text) }
                return QSConversationTurn(id: t.id, who: .ai, text: t.text, proposal: body, label: numbers[t.id].map { "v\($0)" })
            case .hand, .back:
                return QSConversationTurn(id: t.id, who: .event, text: t.text + (numbers[t.id].map { " (v\($0))" } ?? ""))
            }
        }
    }

    /// What the newest version changed against the one before, line by line.
    private func changes(_ draft: DraftItem) -> some View {
        let vs = versions(draft)
        let idx = vs.lastIndex(where: { $0.turn.body == draft.body }) ?? vs.count - 1
        let old = idx > 0 ? vs[idx - 1].turn.body!.components(separatedBy: "\n") : []
        let new = draft.body.components(separatedBy: "\n")
        let diff = new.difference(from: old)
        let removed = Set(diff.removals.map { if case .remove(let o, _, _) = $0 { return o } else { return -1 } })
        let inserted = Set(diff.insertions.map { if case .insert(let o, _, _) = $0 { return o } else { return -1 } })
        // Walk both texts together: a removed line shows where it was, struck through; an added one in green.
        var lines: [(kind: Int, text: String)] = []
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count && removed.contains(i) { lines.append((-1, old[i])); i += 1 }
            else if j < new.count && inserted.contains(j) { lines.append((1, new[j])); j += 1 }
            else { if j < new.count { lines.append((0, new[j])) }; i += 1; j += 1 }
        }
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                Text(l.text.isEmpty ? " " : l.text).font(Theme.Text.body)
                    .strikethrough(l.kind < 0)
                    .foregroundStyle(l.kind < 0 ? Theme.Palette.prFailing : l.kind > 0 ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(l.kind < 0 ? Theme.Palette.prFailing.opacity(0.08) : l.kind > 0 ? Theme.Palette.prOpen.opacity(0.15) : .clear)
            }
        }
        .textSelection(.enabled)
    }

    private func card(_ draft: DraftItem) -> some View {
        let isSelected = selected.contains(draft.id)
        return HStack(alignment: .top, spacing: Theme.Space.m) {
            Button {
                if isSelected { selected.remove(draft.id) } else { selected.insert(draft.id) }
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Theme.Text.heroTitle)
                    .foregroundStyle(isSelected ? Theme.Palette.accent : Theme.Palette.textTertiary)
            }
            .buttonStyle(QSHoverStyle(padding: 2))
            .help(isSelected ? "Unselect" : "Select, to archive it once posted")

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    QSTag(text: draft.place, icon: "paperplane", color: Theme.Palette.accent)
                    Text(QSDate.ago(draft.created)).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textTertiary)
                    Spacer()
                    if draft.place == "Slack" {
                        if store.draftingIds.contains(draft.id) {
                            ProgressView().controlSize(.small)
                            Text("Drafting…").font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                        } else {
                            if draft.drafted { QSTag(text: "In your Slack drafts", icon: "checkmark", color: Theme.Palette.prOpen) }
                            Button { Task { await store.draftInSlack(draft) } } label: {
                                Label(draft.drafted ? "Draft again" : "Draft in Slack", systemImage: "paperplane")
                            }
                            .buttonStyle(QSHoverStyle())
                            .help("Leaves it as a draft in your Slack, in the right channel. It is not sent. Slack keeps one draft per channel, so an old one has to be deleted there first.")
                        }
                    }
                    if editingId != draft.id {
                        QSIconButton(systemImage: "pencil", help: "Edit the text") { editingId = draft.id; editText = draft.body; previewing = false }
                    }
                    let said = (store.draftTurns[draft.id] ?? []).filter { $0.who == .me }.count
                    Button {
                        if talking.contains(draft.id) { talking.remove(draft.id) } else { talking.insert(draft.id) }
                    } label: {
                        Label(said == 0 ? "Talk" : "Talk (\(said))", systemImage: store.talkingIds.contains(draft.id) ? "ellipsis.bubble.fill" : "bubble.left.and.bubble.right")
                    }
                    .buttonStyle(QSHoverStyle())
                    .foregroundStyle(talking.contains(draft.id) ? Theme.Palette.accent : Theme.Palette.textPrimary)
                    .help("Talk with the agent that wrote it: ask for changes, answer its questions")
                    if let link = draft.link {
                        QSOpenLinkButton(url: link, help: "Open where it goes")
                    }
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(draft.body, forType: .string)
                    }
                    .buttonStyle(QSHoverStyle())
                    .help("Copy the text")
                }
                if !draft.note.isEmpty {
                    Text(draft.note).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                }
                if editingId == draft.id {
                    Picker("", selection: $previewing) {
                        Text("Edit").tag(false)
                        Text("Preview").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                    if previewing {
                        DraftPreview(text: editText, place: draft.place)
                            .padding(Theme.Space.m)
                            .frame(maxWidth: .infinity, minHeight: Theme.Size.editorMinHeight, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.well))
                    } else {
                        TextEditor(text: $editText)
                            .font(Theme.Text.body)
                            .scrollContentBackground(.hidden)
                            .padding(Theme.Space.s)
                            .frame(minHeight: Theme.Size.editorMinHeight)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.well))
                    }
                    HStack(spacing: Theme.Space.m) {
                        if draft.drafted {
                            Text("It was already in Slack: saving makes it a new text to draft again.")
                                .font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary)
                        }
                        Spacer()
                        Button("Cancel") { editingId = nil }.keyboardShortcut(.cancelAction).buttonStyle(QSHoverStyle())
                        Button("Save") {
                            store.editDraft(draft.id, body: editText)
                            editingId = nil
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(QSHoverStyle())
                        .foregroundStyle(Theme.Palette.accent)
                        .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else if showChanges.contains(draft.id) && versions(draft).count > 1 {
                    changes(draft)
                } else {
                    DraftPreview(text: draft.body, place: draft.place)
                }
                if talking.contains(draft.id) || store.talkingIds.contains(draft.id) { thread(draft) }
            }
        }
        .padding(Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.surface)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(isSelected ? Theme.Palette.highlight : .clear)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
    }
}
