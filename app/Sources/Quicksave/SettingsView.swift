import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var key = ""
    @State private var saved = Database.shared.secret("linearApiKey") != nil

    var body: some View {
        Form {
            Section {
                SecureField("Linear API key", text: $key, prompt: Text(saved ? "Saved. Paste a new one to replace it." : "lin_api_…"))
                HStack {
                    Button("Save") {
                        Database.shared.setSecret("linearApiKey", key.trimmingCharacters(in: .whitespacesAndNewlines))
                        key = ""; saved = true
                        Task { await store.refresh() }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if saved {
                        Button("Remove", role: .destructive) {
                            Database.shared.setSecret("linearApiKey", nil); saved = false
                            Task { await store.refresh() }
                        }
                    }
                }
            } footer: {
                Text("Read-only key from Linear > Settings > Account > Security & access. Stored encrypted in Quicksave's local database, tied to this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
