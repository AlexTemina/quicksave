import AppKit
import SwiftUI

extension AgentRunState {
    var title: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Running"
        case .done: return "Done"
        case .needsYou: return "Needs you"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    var color: Color {
        switch self {
        case .queued: return Theme.Palette.runQueued
        case .running: return Theme.Palette.runRunning
        case .done: return Theme.Palette.runDone
        case .needsYou: return Theme.Palette.runNeedsYou
        case .failed: return Theme.Palette.runFailed
        case .cancelled: return Theme.Palette.runCancelled
        }
    }
    var icon: String {
        switch self {
        case .queued: return Theme.Icon.later
        case .running: return Theme.Icon.agentLive
        case .done: return Theme.Icon.accept
        case .needsYou: return "hand.raised.fill"
        case .failed: return "exclamationmark.triangle"
        case .cancelled: return "slash.circle"
        }
    }
}

enum RunFormat {
    static func duration(_ s: TimeInterval?) -> String {
        guard let s else { return "" }
        let t = Int(s.rounded())
        return t < 60 ? "\(t) s" : t < 3600 ? "\(t / 60):\(String(format: "%02d", t % 60))" : "\(t / 3600) h \(t % 3600 / 60) min"
    }
    static func cost(_ c: Double?) -> String { c.map { String(format: "%.2f USD", $0) } ?? "" }
    static func folder(_ path: String) -> String {
        AgentMonitor.lockKey(path) == nil ? "temporary folder" : (path as NSString).abbreviatingWithTildeInPath
    }
    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm:ss" : "EEE d MMM, HH:mm"
        return f.string(from: d)
    }
}

/// Every background agent Quicksave started: the runs on the left, what the picked one did on the right.
/// See docs/background-agents.md.
struct AgentsView: View {
    @ObservedObject var store: Store
    @ObservedObject var monitor = AgentMonitor.shared

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: Theme.Size.runListWidth)
            Divider()
            Group {
                if let run = current { RunDetail(run: run, step: monitor.steps[run.id]) }
                else { QSEmptyState(icon: Theme.Icon.agents, title: "No runs yet", subtitle: "Agents Quicksave starts show up here.") }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(QSWindowBackground())
    }

    private var current: AgentRunRecord? {
        monitor.runs.first { $0.id == monitor.selected } ?? monitor.runs.first
    }

    private var list: some View {
        let live = monitor.live
        let ended = monitor.runs.filter { !$0.state.isLive }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Agents").font(Theme.Text.pageTitle)
                if !live.isEmpty { group("Now", live) }
                group("Earlier", ended)
            }
            .padding(Theme.Space.l)
        }
    }

    @ViewBuilder private func group(_ title: String, _ runs: [AgentRunRecord]) -> some View {
        if !runs.isEmpty {
            QSLabel("\(title) · \(runs.count)").padding(.top, Theme.Space.m)
            ForEach(runs) { run in
                Button { monitor.selected = run.id } label: { row(run) }.buttonStyle(.plain)
            }
        }
    }

    private func row(_ run: AgentRunRecord) -> some View {
        QSCard(highlighted: current?.id == run.id, tint: run.state.isLive ? run.state.color : nil, pulsing: run.state == .running) {
            HStack(spacing: Theme.Space.s) {
                Text(run.job).font(Theme.Text.cardTitle).lineLimit(1)
                Spacer(minLength: 0)
                if !run.denials.isEmpty { QSTag(text: "\(run.denials.count) denied", icon: "nosign", color: Theme.Palette.warning) }
                QSTag(text: run.state == .running ? (monitor.steps[run.id] ?? run.state.title) : run.state.title,
                      icon: run.state.icon, color: run.state.color)
            }
            HStack(spacing: Theme.Space.s) {
                Text(QSDate.ago(run.queued)).foregroundStyle(Theme.Palette.textTertiary)
                Spacer(minLength: 0)
                if run.state.isLive {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in Text(RunFormat.duration(run.duration)) }
                } else {
                    Text(RunFormat.duration(run.duration))
                }
                if run.cost != nil { Text(RunFormat.cost(run.cost)) }
            }
            .font(Theme.Text.meta.monospacedDigit())
            .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}

/// One run in full: its numbers, what was refused, its result, and every step it took.
private struct RunDetail: View {
    let run: AgentRunRecord
    let step: String?
    @State private var entries: [AgentMonitor.Entry] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                    Text(run.job).font(Theme.Text.heroTitle)
                    QSTag(text: run.state.title, icon: run.state.icon, color: run.state.color)
                    Spacer(minLength: 0)
                    if run.state.isLive {
                        QSPrimaryButton(title: "Cancel", icon: Theme.Icon.cancel) { AgentMonitor.shared.cancel(run.id) }
                    }
                }
                numbers
                if run.state == .running, let step { QSNote(text: step, icon: Theme.Icon.agentLive) }
                if let error = run.error { QSNote(text: error, icon: "exclamationmark.triangle", warning: run.state == .failed) }
                if !run.denials.isEmpty {
                    QSLabel("Denied actions · \(run.denials.count)").padding(.top, Theme.Space.s)
                    QSBulletList(lines: run.denials.map { $0.count > 300 ? String($0.prefix(300)) + "…" : $0 })
                }
                if let result = run.result {
                    QSLabel("Result").padding(.top, Theme.Space.s)
                    Text(Self.pretty(result))
                        .font(Theme.Text.code).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Space.m)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.well))
                }
                steps
            }
            .padding(Theme.Space.l)
        }
        .task(id: run.id) { await follow() }
    }

    private var numbers: some View {
        QSFlow(spacing: Theme.Space.m) {
            fact("Started", run.started.map(RunFormat.time) ?? "not yet")
            if run.state.isLive {
                TimelineView(.periodic(from: .now, by: 1)) { _ in fact("Took", RunFormat.duration(run.duration)) }
            } else if run.duration != nil {
                fact("Took", RunFormat.duration(run.duration))
            }
            if run.cost != nil { fact("Cost", RunFormat.cost(run.cost)) }
            if let t = run.turns { fact("Turns", "\(t)") }
            fact("Model", run.model)
            fact("Folder", RunFormat.folder(run.directory))
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Text(label).foregroundStyle(Theme.Palette.textTertiary)
            Text(value).foregroundStyle(Theme.Palette.textSecondary).textSelection(.enabled)
        }
        .font(Theme.Text.meta)
    }

    @ViewBuilder private var steps: some View {
        HStack {
            QSLabel("What it did · \(entries.count)")
            Spacer()
            if let path = run.transcript, FileManager.default.fileExists(atPath: path) {
                Button("Open full output") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                    .buttonStyle(QSHoverStyle()).font(Theme.Text.meta)
            }
        }
        .padding(.top, Theme.Space.s)
        if run.transcript == nil {
            QSNote(text: "The full output is kept for 30 days. This run's is gone.")
        } else if entries.isEmpty {
            QSPlaceholder(text: run.state == .queued ? "Waiting for its turn." : "Nothing recorded yet.")
        }
        ForEach(entries) { e in EntryRow(entry: e) }
    }

    /// Reads the transcript, and again every two seconds while the run is live.
    private func follow() async {
        while !Task.isCancelled {
            if let path = run.transcript {
                entries = await Task.detached { AgentMonitor.entries(path) }.value
            }
            let live = AgentMonitor.shared.runs.first { $0.id == run.id }?.state.isLive ?? false
            if !live { break }
            try? await Task.sleep(for: .seconds(2))
        }
        if let path = run.transcript { entries = await Task.detached { AgentMonitor.entries(path) }.value }
    }

    private static func pretty(_ json: String) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let s = String(data: data, encoding: .utf8) else { return json }
        return s
    }
}

private struct EntryRow: View {
    let entry: AgentMonitor.Entry
    @State private var open = false

    var body: some View {
        switch entry.kind {
        case .said:
            Text(entry.detail).font(Theme.Text.body).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .action:
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Image(systemName: Theme.Icon.agentLive).foregroundStyle(Theme.Palette.runRunning)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(entry.title).font(Theme.Text.label)
                    Text(entry.detail).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(open ? nil : 3).textSelection(.enabled)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { open.toggle() }
        case .output, .failedOutput:
            DisclosureGroup(isExpanded: $open) {
                Text(entry.detail).font(Theme.Text.code).foregroundStyle(Theme.Palette.textSecondary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(entry.title).font(Theme.Text.meta)
                    .foregroundStyle(entry.kind == .failedOutput ? Theme.Palette.runFailed : Theme.Palette.textTertiary)
            }
            .padding(.leading, Theme.Space.l)
        }
    }
}

/// What is running now, on every tab, with a way to stop it.
struct AgentStrip: View {
    @ObservedObject var store: Store
    @ObservedObject var monitor = AgentMonitor.shared

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            ForEach(monitor.live) { run in
                HStack(spacing: Theme.Space.s) {
                    Button {
                        monitor.selected = run.id
                        store.tab = .agents
                    } label: {
                        HStack(spacing: Theme.Space.s) {
                            QSDot(color: run.state.color, size: Theme.Size.smallDot)
                            Text(run.job).font(Theme.Text.label)
                            Text(run.state == .running ? (monitor.steps[run.id] ?? "Running") : "Queued")
                                .foregroundStyle(Theme.Palette.textSecondary)
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Text(RunFormat.duration(run.duration)).foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                        .font(Theme.Text.meta.monospacedDigit())
                    }
                    .buttonStyle(QSHoverStyle())
                    QSIconButton(systemImage: Theme.Icon.cancel, help: "Cancel this run") { monitor.cancel(run.id) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.xs)
        .background(Theme.Palette.raised)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Palette.hairline).frame(height: 1) }
    }
}
