import Foundation

struct LinearIssue: Decodable {
    struct State: Decodable { let name: String; let type: String; let color: String? }
    struct Attachment: Decodable {
        struct Meta: Decodable { let status: String?; let number: Int?; let draft: Bool? }
        let url: String
        let title: String?
        let metadata: Meta?
    }
    struct Attachments: Decodable { let nodes: [Attachment] }
    struct Relation: Decodable { let type: String; let relatedIssue: LinearIssue? ; let issue: LinearIssue? }
    struct Relations: Decodable { let nodes: [Relation] }
    let identifier: String
    let title: String
    let description: String?
    let url: String
    let dueDate: String?
    let createdAt: String?
    let state: State
    let attachments: Attachments?
    let relations: Relations?
    let inverseRelations: Relations?
}

/// Read-only Linear client. One GraphQL query returns the open Main Quest with its related pieces.
enum Linear {
    private static let pieceFields = "identifier title description url dueDate state { name type color } attachments { nodes { url title metadata } }"

    struct Board { let quests: [LinearIssue]; let stateColors: [String: String] }

    static func openMainQuests(key: String) async throws -> Board {
        let query = """
        query {
          issues(first: 5, filter: {
            labels: { name: { eq: "Main Quest" } },
            assignee: { isMe: { eq: true } },
            state: { type: { nin: ["completed", "canceled"] } }
          }) {
            nodes {
              \(pieceFields)
              relations { nodes { type relatedIssue { \(pieceFields) } } }
              inverseRelations { nodes { type issue { \(pieceFields) } } }
            }
          }
          workflowStates(first: 100, filter: { team: { key: { in: ["ES", "TEMI"] } } }) {
            nodes { name color team { key } }
          }
        }
        """
        let data = try await send(query, key: key)
        struct Envelope: Decodable {
            struct DataPart: Decodable {
                struct Issues: Decodable { let nodes: [LinearIssue] }
                struct WState: Decodable { struct Team: Decodable { let key: String }; let name: String; let color: String; let team: Team }
                struct WStates: Decodable { let nodes: [WState] }
                let issues: Issues
                let workflowStates: WStates
            }
            struct GQLError: Decodable { let message: String }
            let data: DataPart?
            let errors: [GQLError]?
        }
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        if let e = env.errors?.first { throw QuicksaveError.message("Linear: \(e.message)") }
        guard let d = env.data else { return Board(quests: [], stateColors: [:]) }
        var colors: [String: String] = [:]
        for st in d.workflowStates.nodes.sorted(by: { $0.team.key == "ES" && $1.team.key != "ES" }) where colors[st.name] == nil {
            colors[st.name] = st.color
        }
        return Board(quests: d.issues.nodes, stateColors: colors)
    }

    /// The auditor files what needs his judgment in this Linear project, in the Triage state.
    static let auditorProjectId = "f323fc7d-349a-45e3-9704-af9a7633bb83"

    /// Items of the Auditor project still in Triage, oldest first.
    static func auditorTriage(key: String) async throws -> [LinearIssue] {
        let query = """
        query {
          issues(first: 100, filter: {
            project: { id: { eq: "\(auditorProjectId)" } },
            state: { type: { eq: "triage" } }
          }) {
            nodes { identifier title description url dueDate createdAt state { name type color } }
          }
        }
        """
        let data = try await send(query, key: key)
        struct Envelope: Decodable {
            struct DataPart: Decodable { struct Issues: Decodable { let nodes: [LinearIssue] }; let issues: Issues }
            struct GQLError: Decodable { let message: String }
            let data: DataPart?
            let errors: [GQLError]?
        }
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        if let e = env.errors?.first { throw QuicksaveError.message("Linear: \(e.message)") }
        return (env.data?.issues.nodes ?? []).sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
    }

    /// The state an issue is in now, by its code (TEMI-516).
    static func issueState(key: String, id: String) async throws -> String? {
        let data = try await send("query { issue(id: \"\(id)\") { state { name } } }", key: key)
        struct Envelope: Decodable {
            struct DataPart: Decodable { struct Issue: Decodable { struct State: Decodable { let name: String }; let state: State }; let issue: Issue? }
            let data: DataPart?
        }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.data?.issue?.state.name
    }

    /// How many Auditor items sit in Todo: approved, waiting for the agent to execute them.
    static func auditorTodoCount(key: String) async throws -> Int {
        try await auditorTodo(key: key).count
    }

    /// The codes of the Auditor items in Todo.
    static func auditorTodo(key: String) async throws -> [String] {
        let query = """
        query {
          issues(first: 100, filter: {
            project: { id: { eq: "\(auditorProjectId)" } },
            state: { name: { eq: "Todo" } }
          }) { nodes { identifier } }
        }
        """
        let data = try await send(query, key: key)
        struct Envelope: Decodable {
            struct DataPart: Decodable { struct Issues: Decodable { struct Node: Decodable { let identifier: String }; let nodes: [Node] }; let issues: Issues }
            struct GQLError: Decodable { let message: String }
            let data: DataPart?
            let errors: [GQLError]?
        }
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        if let e = env.errors?.first { throw QuicksaveError.message("Linear: \(e.message)") }
        return (env.data?.issues.nodes ?? []).map(\.identifier)
    }

    /// An issue as the queue and the collectibles show it.
    struct QueueIssue: Decodable, Identifiable, Hashable {
        struct State: Decodable, Hashable { let name: String; let type: String; let color: String? }
        struct Named: Decodable, Hashable { let name: String }
        struct Labels: Decodable, Hashable { let nodes: [Named] }
        let identifier: String
        let title: String
        let url: String
        let dueDate: String?
        /// 0 none, 1 urgent, 2 high, 3 medium, 4 low.
        let priority: Int?
        let estimate: Double?
        let state: State
        let labels: Labels?
        var id: String { identifier }
        var isOpen: Bool { !["completed", "canceled"].contains(state.type) && state.name != "Duplicate" }
        var labelNames: [String] { (labels?.nodes ?? []).map(\.name) }
    }

    private static let queueFields = "identifier title url dueDate priority estimate state { name type color } labels { nodes { name } }"

    private struct GQLError: Decodable { let message: String }

    /// Issues by their codes, in one request, whatever their state.
    static func issues(key: String, ids: [String]) async throws -> [QueueIssue] {
        guard !ids.isEmpty else { return [] }
        let parts = ids.enumerated().map { i, id in "i\(i): issue(id: \"\(id)\") { \(queueFields) }" }
        let data = try await send("query { \(parts.joined(separator: "\n")) }", key: key)
        struct Envelope: Decodable { let data: [String: QueueIssue?]?; let errors: [GQLError]? }
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        let found = env.data ?? [:]
        return ids.indices.compactMap { found["i\($0)"] ?? nil }
    }

    /// Issues by their codes with everything a piece card shows (description, pull requests), whatever their state.
    static func pieces(key: String, ids: [String]) async throws -> [LinearIssue] {
        guard !ids.isEmpty else { return [] }
        let parts = ids.enumerated().map { i, id in "i\(i): issue(id: \"\(id)\") { \(pieceFields) }" }
        let data = try await send("query { \(parts.joined(separator: "\n")) }", key: key)
        struct Envelope: Decodable { let data: [String: LinearIssue?]? }
        let found = (try JSONDecoder().decode(Envelope.self, from: data)).data ?? [:]
        return ids.indices.compactMap { found["i\($0)"] ?? nil }
    }

    /// His open issues, every team. With `label`, only those carrying it.
    static func myOpenIssues(key: String, label: String? = nil) async throws -> [QueueIssue] {
        let labelFilter = label.map { ", labels: { name: { eq: \"\($0)\" } }" } ?? ""
        let query = """
        query { issues(first: 200, filter: {
          assignee: { isMe: { eq: true } }, state: { type: { nin: ["completed", "canceled"] } }\(labelFilter)
        }) { nodes { \(queueFields) } } }
        """
        let data = try await send(query, key: key)
        struct Envelope: Decodable {
            struct DataPart: Decodable { struct Issues: Decodable { let nodes: [QueueIssue] }; let issues: Issues }
            let data: DataPart?
            let errors: [GQLError]?
        }
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        if let e = env.errors?.first { throw QuicksaveError.message("Linear: \(e.message)") }
        return (env.data?.issues.nodes ?? []).filter(\.isOpen)
    }

    /// An issue's description as Linear holds it right now, read just before rewriting it.
    static func description(key: String, id: String) async throws -> String {
        let data = try await send("query { issue(id: \"\(id)\") { description } }", key: key)
        struct Envelope: Decodable { struct DataPart: Decodable { struct I: Decodable { let description: String? }; let issue: I? }; let data: DataPart? }
        guard let issue = try JSONDecoder().decode(Envelope.self, from: data).data?.issue else {
            throw QuicksaveError.message("Linear does not know \(id).")
        }
        return issue.description ?? ""
    }

    struct IssuePreview: Decodable {
        struct State: Decodable { let name: String; let color: String? }
        struct Named: Decodable { let name: String }
        struct Labels: Decodable { let nodes: [Named] }
        let identifier: String
        let title: String
        let description: String?
        let dueDate: String?
        let priorityLabel: String?
        let state: State
        let assignee: Named?
        let project: Named?
        let labels: Labels?
    }

    /// What a hover card shows of an issue, by its code (ES-12785).
    static func issuePreview(key: String, id: String) async throws -> IssuePreview? {
        let query = """
        query { issue(id: "\(id)") {
          identifier title description dueDate priorityLabel state { name color } assignee { name } project { name }
          labels { nodes { name } }
        } }
        """
        let data = try await send(query, key: key)
        struct Envelope: Decodable {
            struct DataPart: Decodable { let issue: IssuePreview? }
            struct GQLError: Decodable { let message: String }
            let data: DataPart?
            let errors: [GQLError]?
        }
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        if let e = env.errors?.first { throw QuicksaveError.message("Linear: \(e.message)") }
        return env.data?.issue
    }

    private static func send(_ query: String, key: String) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.linear.app/graphql")!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw QuicksaveError.message("Linear answered \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }
        return data
    }
}
