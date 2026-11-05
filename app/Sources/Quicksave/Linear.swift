import Foundation

struct LinearIssue: Decodable {
    struct State: Decodable { let name: String; let type: String; let color: String? }
    struct Relation: Decodable { let type: String; let relatedIssue: LinearIssue? ; let issue: LinearIssue? }
    struct Relations: Decodable { let nodes: [Relation] }
    let identifier: String
    let title: String
    let description: String?
    let url: String
    let dueDate: String?
    let state: State
    let relations: Relations?
    let inverseRelations: Relations?
}

/// Read-only Linear client. One GraphQL query returns the open Main Quest with its related pieces.
enum Linear {
    private static let pieceFields = "identifier title description url dueDate state { name type color }"

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
        var req = URLRequest(url: URL(string: "https://api.linear.app/graphql")!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw QuicksaveError.message("Linear answered \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }
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
}
