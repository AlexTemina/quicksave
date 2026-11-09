import AppKit
import SwiftUI
import Foundation

enum AppTab: Hashable { case today, inbox, drafts }

@MainActor
final class Store: ObservableObject {
    @Published var tab: AppTab = {
        switch ProcessInfo.processInfo.environment["QUICKSAVE_TAB"] {
        case "inbox": return .inbox
        case "drafts": return .drafts
        default: return .today
        }
    }()

    // The morning: plan the day, choose the game, write the standup. Kept in memory until he starts over, so closing
    // the panel loses nothing. See docs/morning.md.
    @Published var morningOpen = ProcessInfo.processInfo.environment["QUICKSAVE_MORNING"] == "1"
    @Published var morningComments = ""
    @Published var morningContinueAnyway = false
    @Published var morningPlan: MorningPlan?
    @Published var morningProposing = false
    @Published var morningApproved = false
    @Published var morningWriting = false
    @Published var morningWritten: MorningWriteResult?
    @Published var morningNotice: String?
    @Published var gameOptions: [GameOption] = []
    @Published var gamesLoading = false
    @Published var gameHistory: [GameEntry] = []
    @Published var standupWriting = false
    @Published var standupDone = false
    @Published var standupNotes = ""
    @Published var standupSkipped = false
    private var morningPlanJSON: String?
    private var morningRounds: [(plan: String, correction: String)] = []
    private var offeredGames: [String] = []
    private var morningDay = Morning.today

    var morningBusy: Bool { morningProposing || morningWriting || gamesLoading || standupWriting }

    func openMorning() {
        if morningDay != Morning.today && !morningBusy { resetMorning() }
        morningOpen = true
    }

    func resetMorning() {
        morningComments = ""; morningContinueAnyway = false; morningPlan = nil; morningPlanJSON = nil; morningRounds = []
        morningApproved = false; morningWritten = nil; morningNotice = nil; gameOptions = []; offeredGames = []
        standupDone = false; standupNotes = ""; standupSkipped = false; morningDay = Morning.today
    }

    func loadGameHistory() {
        Database.shared.importGamesFromVaultIfEmpty()
        gameHistory = Database.shared.games()
    }

    /// Asks for a plan, or for a new one with his correction applied. Nothing is written.
    func proposePlan(correction: String?) async {
        guard !morningProposing, !applying else { return }
        if let correction, let current = morningPlanJSON { morningRounds.append((current, correction)) }
        morningProposing = true
        morningNotice = nil
        defer { morningProposing = false }
        do {
            let run = try await Agents.run(.morningPlan(comments: morningComments, rounds: morningRounds))
            morningPlan = try JSONDecoder().decode(MorningPlan.self, from: Data(run.resultJSON.utf8))
            morningPlanJSON = run.resultJSON
        } catch {
            if correction != nil { morningRounds.removeLast() }
            morningNotice = "The plan could not be made: \(error.localizedDescription)"
        }
    }

    /// He approved: the plan is written to Linear, and the games are looked for at the same time.
    func approvePlan() async {
        guard let plan = morningPlan, let json = morningPlanJSON, !morningApproved, !applying else { return }
        morningApproved = true
        morningNotice = nil
        async let games: Void = loadGames()
        if plan.writes { await writePlan() }
        await games
    }

    /// Writes the approved plan to Linear. The agent creates or moves the Main Quest; the side quests are written by
    /// the app itself, the same way as "Add to today". Called again from "Try again": a part already written is not
    /// written twice.
    func writePlan() async {
        guard let plan = morningPlan, let json = morningPlanJSON, morningApproved, !morningWriting, !applying else { return }
        morningWriting = true
        defer { morningWriting = false }
        var result = morningWritten
        if plan.action != "keep", result?.mainQuestDone != true {
            do {
                let run = try await Agents.run(.morningWrite(plan: json))
                var decoded = try JSONDecoder().decode(MorningWriteResult.self, from: Data(run.resultJSON.utf8))
                decoded.mainQuestDone = decoded.outcome == "done"
                result = decoded
            } catch {
                result = MorningWriteResult(outcome: "failed", summary: "It could not be written: \(error.localizedDescription)",
                                            identifier: nil, url: nil)
            }
        } else if result == nil {
            result = MorningWriteResult(outcome: "done", summary: "The open Main Quest stays as it is.",
                                        identifier: plan.existing, url: quest?.url?.absoluteString, mainQuestDone: true)
        }
        let sides = plan.sideQuests ?? []
        if result?.mainQuestDone == true, !sides.isEmpty, result?.sideQuestsDone != true,
           let mq = result?.identifier.flatMap({ $0.isEmpty ? nil : $0 }) ?? plan.existing {
            do {
                try await PlanWrites.change(mainQuest: mq) { SideQuestPlan.replacing(sides.map(SideQuestPlan.line), in: $0) }
                result?.sideQuestsDone = true
                result?.summary += " \(sides.count) side quest\(sides.count == 1 ? "" : "s") written in the plan."
            } catch {
                result?.outcome = "failed"
                result?.summary += " The side quests could not be written: \(error.localizedDescription)"
            }
        }
        morningWritten = result
        await refresh()
    }

    /// Five games for today, never one already used or already offered.
    func loadGames() async {
        guard !gamesLoading else { return }
        gamesLoading = true
        defer { gamesLoading = false }
        if gameHistory.isEmpty { loadGameHistory() }
        let used = gameHistory.map(\.game)
        let usedKeys = Set(used.map(GameOption.key))
        var mood = "His comments: \(morningComments.isEmpty ? "none" : morningComments)"
        if let plan = morningPlan { mood += "\nToday's Main Quest: \(plan.goal). Why: \(plan.why)\nMeetings: \(plan.meetings.joined(separator: "; "))" }
        do {
            let run = try await Agents.run(.games(mood: mood, used: used, offered: offeredGames))
            let fresh = try JSONDecoder().decode(GameOptions.self, from: Data(run.resultJSON.utf8)).games
                .filter { !usedKeys.contains(GameOption.key($0.game)) && !offeredGames.contains($0.game) }
            offeredGames += fresh.map(\.game)
            gameOptions = fresh
        } catch {
            morningNotice = "No games came back: \(error.localizedDescription)"
        }
    }

    /// Writes the standup with the game he chose, leaves it in Drafts and logs the game so it never repeats.
    func writeStandup(game: GameOption, score: String) async {
        guard !standupWriting, let json = morningPlanJSON else { return }
        standupWriting = true
        morningNotice = nil
        defer { standupWriting = false }
        do {
            let run = try await Agents.run(.standup(plan: json, comments: morningComments, score: score, game: game))
            let result = try JSONDecoder().decode(StandupResult.self, from: Data(run.resultJSON.utf8))
            let thread = result.threadLink.flatMap { $0.isEmpty ? nil : $0 }
            Database.shared.addDraft(place: "Slack",
                                     note: "Standup: reply in the thread of today's Spain Area Standup in #area_spain.",
                                     link: thread, body: result.text, source: "morning",
                                     item: morningWritten?.identifier ?? morningPlan?.existing)
            Database.shared.addGame(date: Morning.today, score: score, game: game.game, simile: game.simile, link: game.link)
            loadDrafts()
            loadGameHistory()
            standupNotes = result.notes ?? ""
            standupDone = true
        } catch {
            morningNotice = "The standup could not be written: \(error.localizedDescription)"
        }
    }

    // Drafts: text he posts himself. They live in the local database.
    @Published var drafts: [DraftItem] = []
    @Published var archivedDrafts: [DraftItem] = []

    func loadDrafts() {
        drafts = Database.shared.drafts(archived: false)
        archivedDrafts = Database.shared.drafts(archived: true)
    }

    @Published var draftingIds: Set<Int64> = []
    @Published var draftsNotice: String?

    /// Leaves a Slack draft as a draft in his own Slack (never sent), and opens the channel to show it.
    func draftInSlack(_ draft: DraftItem) async {
        guard !draftingIds.contains(draft.id) else { return }
        draftingIds.insert(draft.id)
        draftsNotice = nil
        defer { draftingIds.remove(draft.id) }
        do {
            let run = try await Agents.run(.slackDraft(text: draft.body, note: draft.note, link: draft.link?.absoluteString))
            let result = try JSONDecoder().decode(SlackDraftResult.self, from: Data(run.resultJSON.utf8))
            if result.outcome == "drafted" {
                Database.shared.markDrafted(draft.id, link: result.link)
                loadDrafts()
                if let url = result.link.flatMap(URL.init) ?? draft.link { NSWorkspace.shared.open(url) }
            } else {
                draftsNotice = "The Slack draft was not created: \(result.summary)"
            }
        } catch {
            draftsNotice = "The Slack draft could not be created: \(error.localizedDescription)"
        }
    }

    @Published var rewritingId: Int64?

    /// Asks an agent to rewrite a draft's text following his instruction. Nothing is saved: the text comes back to the
    /// editor and he decides.
    func rewriteDraft(_ draft: DraftItem, text: String, instruction: String, useContext: Bool) async -> (text: String, notes: String)? {
        rewritingId = draft.id
        draftsNotice = nil
        defer { rewritingId = nil }
        do {
            let run = try await Agents.run(.rewriteDraft(place: draft.place, note: draft.note, link: draft.link?.absoluteString,
                                                         item: draft.item, text: text, instruction: instruction, useContext: useContext))
            let result = try JSONDecoder().decode(DraftRewriteResult.self, from: Data(run.resultJSON.utf8))
            return (result.text, result.notes ?? "")
        } catch {
            draftsNotice = "The AI could not rewrite it: \(error.localizedDescription)"
            return nil
        }
    }

    func editDraft(_ id: Int64, body: String) {
        Database.shared.updateDraftBody(id, body)
        loadDrafts()
    }

    func setArchived(_ ids: [Int64], _ archived: Bool) {
        Database.shared.setDraftsArchived(ids, archived)
        loadDrafts()
    }

    // The inbox. A decision on a Triage card is written to Linear at once; one on a pull request waits in the
    // local database until Apply. See docs/inbox.md.
    @Published var inbox: [InboxCard] = []
    @Published var inboxError: String?
    /// A write that failed, said once, until the next decision.
    @Published var inboxNotice: String?
    @Published var inboxLoaded = false
    @Published var decisions: [String: InboxDecision] = [:]
    /// Cards whose write to Linear is still going.
    @Published var writing: Set<String> = []
    /// Items of the Auditor project in Todo: approved, waiting for the agent.
    @Published var approvedCount = 0
    @Published var applying = false
    /// What Apply is doing right now, in a few words.
    @Published var applyStep = ""
    @Published var report: ApplyReport?
    @Published private var deferred: [String] = []
    @Published private var stack: [(card: InboxCard, decision: InboxDecision)] = []
    /// Writes to Linear run one after another, so an undo never overtakes the decision it undoes.
    private var chain: Task<Void, Never>?

    @Published var quest: MainQuest?
    /// Today's side quests, read live from the issues the Main Quest lists.
    @Published var sideQuests: [SideQuest] = []
    @Published var collectibles: [Linear.QueueIssue] = []
    /// Side quests being added or taken out right now.
    @Published var planWriting: Set<String> = []
    @Published var planNotice: String?
    @Published var stateColors: [String: String] = [:]
    @Published var worktrees: [String: Orca.Match] = [:]
    @Published var prStatus: [Int: GitHub.Status] = [:]
    @Published var error: String?
    @Published var loading = false
    @Published var lastRefresh: Date?

    private var timer: Timer?
    private var observer: NSObjectProtocol?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { await self?.refresh() } }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refresh() }
        }
        loadDrafts()
        Task { await refresh() }
    }

    func refresh() async {
        if loading { return }
        loading = true
        defer { loading = false }
        do {
            guard let key = Database.shared.secret("linearApiKey") else {
                throw QuicksaveError.message("Add your Linear API key in Settings (⌘,).")
            }
            await refreshInbox(key: key)
            let board = try await Linear.openMainQuests(key: key)
            let open = board.quests
            stateColors = board.stateColors
            quest = open.first.map(MainQuest.init)
            error = open.count > 1 ? "\(open.count) Main Quests are open. Only one should be." : nil
            lastRefresh = Date()
            var found: [String: Orca.Match] = [:]
            for piece in quest?.pieces ?? [] { if let m = await Orca.worktree(for: piece.id) { found[piece.id] = m } }
            worktrees = found
            var statuses: [Int: GitHub.Status] = [:]
            for pr in (quest?.pieces ?? []).flatMap(\.pullRequests) {
                if let st = await GitHub.status(of: pr) { statuses[pr.number] = st }
            }
            prStatus = statuses
            await refreshQueue(key: key)
            Snapshot.boardIfAsked(self)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refreshQueue(key: String) async {
        let plan = quest?.sideQuestPlan ?? []
        if let issues = try? await Linear.issues(key: key, ids: plan.map(\.id)) {
            sideQuests = plan.compactMap { line in
                issues.first { $0.identifier == line.id }.map { SideQuest(issue: $0, note: line.note) }
            }
        }
        if let found = try? await Linear.myOpenIssues(key: key, label: "collectible") { collectibles = QueueOrder.sorted(found) }
    }

    /// His open issues that could join today: not the Main Quest, its pieces, today's side quests or collectibles.
    func issuesToAdd() async -> [Linear.QueueIssue] {
        guard let key = Database.shared.secret("linearApiKey"), let all = try? await Linear.myOpenIssues(key: key) else { return [] }
        var taken = Set(sideQuests.map(\.id) + (quest?.pieces.map(\.id) ?? []))
        if let q = quest { taken.insert(q.identifier) }
        return QueueOrder.sorted(all.filter { !taken.contains($0.identifier) && !$0.labelNames.contains("collectible") })
    }

    func addToToday(_ issue: Linear.QueueIssue) async {
        await changePlan(issue.identifier) { SideQuestPlan.adding(issue, to: $0) }
    }

    func removeFromToday(_ id: String) async {
        await changePlan(id) { SideQuestPlan.removing(id, from: $0) }
    }

    private func changePlan(_ id: String, _ edit: @escaping (String) -> String) async {
        guard let mq = quest?.identifier, !planWriting.contains(id) else { return }
        planWriting.insert(id)
        planNotice = nil
        defer { planWriting.remove(id) }
        do {
            try await PlanWrites.change(mainQuest: mq, edit)
            await refresh()
        } catch {
            planNotice = "\(id) could not be changed in the plan: \(error.localizedDescription)"
        }
    }

    func color(of state: String, fallback: String) -> Color { Color(hex: stateColors[state] ?? fallback) }

    // MARK: Inbox

    /// What is still to decide: cards left for later go behind the rest, in the order they were left.
    var pendingCards: [InboxCard] {
        let open = inbox.filter { decisions[$0.id] == nil }
        let fresh = open.filter { !deferred.contains($0.id) }
        let later = deferred.compactMap { id in open.first { $0.id == id } }
        return fresh + later
    }
    var currentCard: InboxCard? { pendingCards.first }
    /// Pull requests with a decision waiting for Apply.
    private var decidedPullRequests: [(pr: VaultPullRequest, decision: InboxDecision)] {
        inbox.compactMap { card in
            if case .pullRequest(let pr) = card, let d = decisions[card.id] { return (pr, d) }
            return nil
        }.sorted { $0.pr.number < $1.pr.number }
    }
    /// What Apply will do: items waiting in Todo, plus pull requests to merge or close.
    var applyCount: Int { approvedCount + decidedPullRequests.count }
    var lastDecided: (card: InboxCard, decision: InboxDecision)? { stack.last }

    func decide(_ card: InboxCard, _ decision: InboxDecision) {
        inboxNotice = nil
        decisions[card.id] = decision
        deferred.removeAll { $0 == card.id }
        stack.append((card, decision))
        switch card {
        case .pullRequest:
            Database.shared.setPRDecision(card.id, decision.prRaw)
        case .triage(let item):
            writing.insert(item.id)
            enqueue { [self] in
                do {
                    try await InboxWrites.write(decision, for: item)
                    await refreshApprovedCount()
                } catch {
                    decisions[item.id] = nil
                    stack.removeAll { $0.card.id == item.id }
                    inboxNotice = "\(item.id) could not be saved, so its card is back: \(error.localizedDescription)"
                }
                writing.remove(item.id)
            }
        }
    }

    func later(_ card: InboxCard) {
        deferred.removeAll { $0 == card.id }
        deferred.append(card.id)
    }

    /// Takes back the last decision: a Triage item goes back to Triage, a pull request just forgets it.
    func undo() {
        guard let last = stack.popLast() else { return }
        inboxNotice = nil
        switch last.card {
        case .pullRequest:
            decisions[last.card.id] = nil
            Database.shared.setPRDecision(last.card.id, nil)
        case .triage(let item):
            writing.insert(item.id)
            enqueue { [self] in
                do {
                    try await InboxWrites.undo(last.decision, for: item)
                    decisions[item.id] = nil
                    if !inbox.contains(where: { $0.id == item.id }) {
                        inbox.append(last.card)
                        inbox.sort { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }
                    }
                    await refreshApprovedCount()
                } catch {
                    stack.append(last)
                    inboxNotice = "\(item.id) could not go back to Triage: \(error.localizedDescription)"
                }
                writing.remove(item.id)
            }
        }
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = chain
        chain = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    private func refreshApprovedCount() async {
        guard let key = Database.shared.secret("linearApiKey"), let n = try? await Linear.auditorTodoCount(key: key) else { return }
        approvedCount = n
    }

    /// Merges or closes the pull requests he decided on, then starts one agent for everything approved in Linear.
    func apply() async {
        guard !applying, applyCount > 0 else { return }
        applying = true
        inboxNotice = nil
        defer { applying = false }
        await chain?.value

        var out = ApplyReport()
        defer { applyStep = "" }

        for (pr, decision) in decidedPullRequests {
            applyStep = "Merging #\(pr.number)…"
            let merging = decision == .accept
            let args = merging ? ["pr", "merge", "\(pr.number)", "--repo", GitHub.vaultRepo, "--merge"]
                               : ["pr", "close", "\(pr.number)", "--repo", GitHub.vaultRepo]
            if let problem = await GitHub.perform(args) {
                out.rows.append(.init(ref: "#\(pr.number)", outcome: .failed, summary: "\(merging ? "Merge" : "Close") failed: \(problem)", links: [pr.url]))
            } else {
                out.rows.append(.init(ref: "#\(pr.number)", outcome: .done, summary: "\(merging ? "Merged" : "Closed"): \(pr.title)", links: [pr.url]))
                decisions[pr.id] = nil
                Database.shared.setPRDecision(pr.id, nil)
            }
        }

        await refreshApprovedCount()
        if approvedCount > 0 {
            let key = Database.shared.secret("linearApiKey")
            var before: [String] = []
            if let key, let ids = try? await Linear.auditorTodo(key: key) { before = ids }
            applyStep = "An agent is reading what you accepted…"
            do {
                let run = try await Agents.run(.apply())
                out.cost = run.cost
                out.seconds = run.seconds
                // One short line per kind of refused action: a whole script pasted in the panel says nothing.
                var seen = Set<String>()
                out.denials = run.denials.map { d in
                    let first = d.components(separatedBy: "\n").first ?? d
                    return first.count > 110 ? String(first.prefix(110)) + "…" : first
                }.filter { seen.insert($0).inserted }
                let result = try JSONDecoder().decode(ApplyAgentResult.self, from: Data(run.resultJSON.utf8))
                for item in result.items {
                    // Code work in a worktree is done by a second agent that runs inside it.
                    if item.outcome == "needs_worktree" {
                        out.rows.append(await workInWorktree(item, totals: &out))
                        continue
                    }
                    let outcome: ApplyReport.Outcome = ["done": .done, "needs_you": .needsYou, "failed": .failed][item.outcome] ?? .skipped
                    var links: [URL] = []
                    for url in (item.links ?? []).compactMap(URL.init) where !links.contains(url) { links.append(url) }
                    out.rows.append(.init(ref: item.id, outcome: outcome, summary: item.summary, links: links))
                }
                for draft in result.drafts {
                    out.drafts.append(.init(place: draft.place, note: draft.note ?? "", link: draft.link.flatMap(URL.init), text: draft.text))
                    Database.shared.addDraft(place: draft.place, note: draft.note ?? "", link: draft.link, body: draft.text, source: "apply", item: draft.item)
                }
                loadDrafts()
                out.notes = result.notes ?? ""

                // The agent may forget to list something it did. Linear is the truth: any item that was waiting
                // and is not in its report gets a row from its real state.
                let listed = Set(result.items.map(\.id))
                for id in before where !listed.contains(id) {
                    var state: String?
                    if let key { state = (try? await Linear.issueState(key: key, id: id)) ?? nil }
                    if state == "Done" {
                        out.rows.append(.init(ref: id, outcome: .done, summary: "Done in Linear. The agent did not list it in its report.", links: []))
                    } else {
                        out.rows.append(.init(ref: id, outcome: .skipped, summary: "Still \(state ?? "unread") in Linear. The agent did not report on it.", links: []))
                    }
                }
            } catch {
                out.rows.append(.init(ref: "Agent", outcome: .failed, summary: error.localizedDescription, links: []))
            }
        }
        report = out
        loading = false
        await refresh()
    }

    /// Runs the task of an item inside its worktree, then moves the item and leaves the summary in Orca.
    /// Success is Done; anything that needs him is Pending for inputs. The app decides that, not the agent.
    private func workInWorktree(_ item: ApplyAgentResult.Item, totals out: inout ApplyReport) async -> ApplyReport.Row {
        func pending(_ why: String) async -> ApplyReport.Row {
            try? await InboxWrites.setState(item.id, "Pending for inputs")
            return .init(ref: item.id, outcome: .needsYou, summary: why, links: [])
        }
        guard let name = item.worktree, let task = item.task, !task.isEmpty else {
            return await pending("It is code work, but the agent did not say in which worktree or what to do.")
        }
        guard let wt = await Orca.worktree(named: name) else {
            return await pending("It is code work in \(name), but Orca does not know a worktree with that name.")
        }
        applyStep = "An agent is working in \(wt.name)…"
        do {
            let run = try await Agents.run(.worktree(item: item.id, directory: wt.path, task: task, comment: wt.comment))
            out.cost = (out.cost ?? 0) + (run.cost ?? 0)
            out.seconds = (out.seconds ?? 0) + run.seconds
            for d in run.denials where !out.denials.contains(d) { out.denials.append(String(d.prefix(110))) }
            let r = try JSONDecoder().decode(WorktreeAgentResult.self, from: Data(run.resultJSON.utf8))
            let outcome: ApplyReport.Outcome = ["done": .done, "needs_you": .needsYou, "failed": .failed][r.outcome] ?? .needsYou
            try? await InboxWrites.setState(item.id, outcome == .done ? "Done" : "Pending for inputs")
            let before = wt.comment.isEmpty ? "" : " · Before: \(wt.comment)"
            await Orca.setComment(worktreeId: wt.id, "\(item.id): \(r.summary) \(r.nextStep)\(before)")
            let match = Orca.Match(worktreeId: wt.id, name: wt.name, liveAgentTerminal: nil)
            return .init(ref: item.id, outcome: outcome,
                         summary: "\(r.summary)\nTests: \(r.tests)\nNext: \(r.nextStep)", links: [], worktree: match)
        } catch {
            var row = await pending("The agent in \(wt.name) could not finish: \(error.localizedDescription)")
            row.worktree = Orca.Match(worktreeId: wt.id, name: wt.name, liveAgentTerminal: nil)
            return row
        }
    }

    private func refreshInbox(key: String) async {
        var cards: [InboxCard] = []
        var problems: [String] = []
        do { cards += try await Linear.auditorTriage(key: key).map { .triage(TriageItem($0)) } }
        catch { problems.append("Triage: \(error.localizedDescription)") }
        let prs = await GitHub.vaultPullRequests()
        if let prs { cards += prs.map { .pullRequest($0) } }
        else { problems.append("Vault pull requests could not be read (is gh logged in?)") }
        inbox = cards.sorted { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }

        // Decisions about pull requests survive closing the app; forget those whose pull request is gone.
        if prs != nil {
            let open = Set(cards.filter(\.isPullRequest).map(\.id))
            for (id, raw) in Database.shared.prDecisions() {
                if !open.contains(id) { Database.shared.setPRDecision(id, nil); continue }
                if decisions[id] == nil, let d = InboxDecision(prRaw: raw) { decisions[id] = d }
            }
        }
        await refreshApprovedCount()
        inboxError = problems.isEmpty ? nil : problems.joined(separator: " ")
        inboxLoaded = true
        Snapshot.inboxIfAsked(cards)
    }
}
