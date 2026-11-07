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
