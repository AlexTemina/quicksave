import Foundation

/// Keeps "Asked of me" fresh: GitHub and Linear every five minutes, Slack, mail and Notion through an agent every
/// thirty. What the agent found and what he dismissed are kept in the local database; they are not task state.
extension Store {
    private static let dismissedKey = "asks.dismissed"
    private static let agentAsksKey = "asks.agent"
    private static let agentSinceKey = "asks.agentSince"

    var dismissedAsks: Set<String> { Set(Database.shared.value(Self.dismissedKey, as: [String].self) ?? []) }

    /// The asks to show: not dismissed, newest first, the ones still waiting on him before the answered ones.
    var visibleAsks: [Ask] {
        let dismissed = dismissedAsks
        return asks.filter { !dismissed.contains($0.id) }.sorted { a, b in
            if a.answered != b.answered { return !a.answered }
            return (a.when) > (b.when)
        }
    }

    /// Waiting on him: not answered at the source, not dismissed, and its card (if any) still open.
    var waitingAsks: [Ask] { visibleAsks.filter { !$0.answered && askCards[$0.id].map(\.isOpen) ?? true } }

    func refreshAsks(key: String, force: Bool = false) async {
        if asks.isEmpty, let saved = Database.shared.value(Self.agentAsksKey, as: [Ask].self) { asks = saved }
        if force || Date().timeIntervalSince(asksLooked ?? .distantPast) > 300 {
            asksLooked = Date()
            asksLoading = true
            defer { asksLoading = false }
            var problems: [String] = []
            var found: [Ask] = []
            do { found += try await Asks.github() } catch { problems.append(error.localizedDescription) }
            do { found += try await Asks.linear(key: key) } catch { problems.append("Linear: " + error.localizedDescription) }
            let fromAgent = Database.shared.value(Self.agentAsksKey, as: [Ask].self) ?? []
            asks = found + fromAgent.filter { a in !found.contains { $0.id == a.id } }
            if let cards = try? await Asks.cards(key: key) {
                var map: [String: AskCard] = [:]
                for a in asks { if let c = Asks.card(for: a, in: cards) { map[a.id] = c } }
                askCards = map
            } else { problems.append("The cards could not be read from Linear.") }
            asksError = problems.isEmpty ? nil : problems.joined(separator: " · ")
            Snapshot.asksIfAsked(self)
        }
        if force || Date().timeIntervalSince(asksAgentLooked ?? .distantPast) > 1800 { lookElsewhere() }
    }

    /// Slack, mail and Notion, through a small agent. Its asks replace the ones it found before with the same link.
    func lookElsewhere() {
        guard !asksAgentRunning else { return }
        asksAgentLooked = Date()
        asksAgentRunning = true
        let since = Database.shared.value(Self.agentSinceKey, as: Date.self) ?? Date().addingTimeInterval(-7 * 86400)
        let known = Database.shared.value(Self.agentAsksKey, as: [Ask].self) ?? []
        let started = Date()
        Task { @MainActor in
            defer { asksAgentRunning = false }
            guard let run = try? await Agents.run(Asks.agentJob(since: since, known: known)),
                  let r = try? JSONDecoder().decode(Asks.AgentResult.self, from: Data(run.resultJSON.utf8)) else {
                asksError = "Slack, mail and Notion could not be read this time."
                return
            }
            let fresh = r.asks.map(Asks.fromAgent)
            let cutoff = Date().addingTimeInterval(-Asks.window)
            let merged = (fresh + known.filter { k in !fresh.contains { $0.id == k.id } })
                .filter { ($0.date ?? Date()) > cutoff }
            Database.shared.setValue(Self.agentAsksKey, merged)
            Database.shared.setValue(Self.agentSinceKey, started)
            asks = asks.filter { !$0.id.hasPrefix("agent:") } + merged
            if let key = Database.shared.secret("linearApiKey"), let cards = try? await Asks.cards(key: key) {
                for a in merged { if let c = Asks.card(for: a, in: cards) { askCards[a.id] = c } }
            }
            Snapshot.asksIfAsked(self, name: "asks-all")
        }
    }

    func dismissAsk(_ ask: Ask) {
        var d = dismissedAsks
        d.insert(ask.id)
        // Kept small: only what is still listed.
        let listed = Set(asks.map(\.id))
        Database.shared.setValue(Self.dismissedKey, Array(d.filter { listed.contains($0) }))
        objectWillChange.send()
    }

    func undismissAll() {
        Database.shared.setValue(Self.dismissedKey, [String]())
        objectWillChange.send()
    }

    func createCard(for ask: Ask) async {
        creatingCard.insert(ask.id)
        defer { creatingCard.remove(ask.id) }
        do {
            let code = try await Asks.createCard(for: ask)
            askCards[ask.id] = AskCard(identifier: code, title: "", url: "https://linear.app/alan-eu/issue/\(code)",
                                       stateName: "Todo", stateType: "unstarted", kind: .answer)
            asksLooked = nil
            if let key = Database.shared.secret("linearApiKey") { await refreshAsks(key: key) }
        } catch {
            asksError = "The card could not be created: \(error.localizedDescription)"
        }
    }
}
