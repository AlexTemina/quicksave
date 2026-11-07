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
    @State private var instruction = ""
    @State private var useContext = true
    /// The text before the last AI rewrite, so it can be reverted.
    @State private var previousText: String?
    @State private var aiNote = ""

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
        .frame(maxWidth: Theme.Size.deckWidth)
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

    /// Asks the AI for a change to the text being edited. The result replaces the text in the editor, nothing is saved.
    private func aiRow(_ draft: DraftItem) -> some View {
        let busy = store.rewritingId == draft.id
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "sparkles").foregroundStyle(Theme.Palette.accent)
                TextField("Ask the AI: shorter, friendlier, add what Bruno said…", text: $instruction)
                    .textFieldStyle(.plain)
                    .padding(Theme.Space.s)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.well))
                    .disabled(busy)
                    .onSubmit { Task { await rewrite(draft) } }
                if busy { ProgressView().controlSize(.small) }
                Button("Rewrite") { Task { await rewrite(draft) } }
                    .buttonStyle(QSHoverStyle())
                    .foregroundStyle(Theme.Palette.accent)
                    .disabled(busy || instruction.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: Theme.Space.m) {
                Toggle("Use context", isOn: $useContext)
                    .toggleStyle(.checkbox).font(Theme.Text.meta)
                    .help("Lets the AI read where the draft came from: the Linear item, the Slack thread. Slower and a bit dearer; leave it off for a change of tone or length.")
                if let previousText {
                    Button("Revert") { editText = previousText; self.previousText = nil; aiNote = "" }
                        .buttonStyle(QSHoverStyle()).font(Theme.Text.meta)
                }
                if !aiNote.isEmpty {
                    Text(aiNote).font(Theme.Text.meta).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
                }
            }
        }
    }

    private func rewrite(_ draft: DraftItem) async {
        let ask = instruction.trimmingCharacters(in: .whitespaces)
        guard !ask.isEmpty, store.rewritingId == nil else { return }
        guard let result = await store.rewriteDraft(draft, text: editText, instruction: ask, useContext: useContext) else { return }
        previousText = editText
        editText = result.text
        aiNote = result.notes
        instruction = ""
        previewing = true
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
                        QSIconButton(systemImage: "pencil", help: "Edit the text") { editingId = draft.id; editText = draft.body; previewing = false
                            instruction = ""; previousText = nil; aiNote = "" }
                    }
                    if let link = draft.link {
                        QSIconButton(systemImage: "arrow.up.right.square", help: "Open where it goes") { NSWorkspace.shared.open(link) }
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
                    aiRow(draft)
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
                } else {
                    DraftPreview(text: draft.body, place: draft.place)
                }
            }
        }
        .padding(Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.surface)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(isSelected ? Theme.Palette.highlight : .clear)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
    }
}
