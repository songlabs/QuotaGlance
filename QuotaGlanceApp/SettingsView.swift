import QuotaGlanceCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Accounts") {
                    ForEach(AIProvider.allCases) { provider in
                        accountRow(provider)
                    }
                }

                Section("Display") {
                    Picker("Default provider", selection: Binding(
                        get: { store.defaultProvider },
                        set: { store.defaultProvider = $0 }
                    )) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Privacy", value: "Credentials stay in Keychain")
                    LabeledContent("Version", value: version)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func accountRow(_ provider: AIProvider) -> some View {
        let connected = store.states[provider]?.isConnected == true
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                Text(connected ? String(localized: "Connected") : String(localized: "Not connected"))
                    .font(.caption)
                    .foregroundStyle(connected ? .green : .secondary)
            }
            Spacer()
            if connected {
                Button("Disconnect", role: .destructive) {
                    Task { await store.disconnect(provider) }
                }
            } else {
                Button("Connect") {
                    dismiss()
                    Task { await store.connect(provider) }
                }
            }
        }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
