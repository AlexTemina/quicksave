import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var key = ""
    @State private var saved = Database.shared.secret("linearApiKey") != nil
    @State private var hotKey = GlobalHotKey.shared.combo

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
            Section {
                LabeledContent("Modifiers") {
                    HStack(spacing: Theme.Space.s) {
                        Toggle("⌃ Control", isOn: $hotKey.control)
                        Toggle("⌥ Option", isOn: $hotKey.option)
                        Toggle("⇧ Shift", isOn: $hotKey.shift)
                        Toggle("⌘ Command", isOn: $hotKey.command)
                    }
                    .toggleStyle(.checkbox)
                }
                Picker("Key", selection: $hotKey.functionKey) {
                    ForEach(1...12, id: \.self) { Text("F\($0)").tag($0) }
                }
            } header: {
                Text("Bring to front: \(hotKey.label)")
            } footer: {
                Text("Works from any app. If Quicksave is already in front, its window glows.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: hotKey) { _, new in GlobalHotKey.shared.combo = new }
        .formStyle(.grouped)
        .frame(width: 540)
    }
}
