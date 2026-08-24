import QuotaGlanceCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var accountPendingDeletion: ProviderAccount?

    var body: some View {
        NavigationStack {
            Form {
                Section("Language") {
                    Picker("Language", selection: $store.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName(locale: locale)).tag(language)
                        }
                    }
                }

                ForEach(AIProvider.allCases) { provider in
                    Section(provider.displayName) {
                        ForEach(store.accounts(for: provider)) { account in
                            accountRow(account)
                        }
                        Button {
                            Task { await store.addAccount(provider) }
                        } label: {
                            Label("Add account", systemImage: "plus")
                        }
                        .disabled(store.connectingProviders.contains(provider))
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

                    ForEach(AIProvider.allCases) { provider in
                        selectedAccountPicker(provider)
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
        .confirmationDialog(
            "Delete account?",
            isPresented: Binding(
                get: { accountPendingDeletion != nil },
                set: { if !$0 { accountPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let account = accountPendingDeletion {
                Button("Delete account", role: .destructive) {
                    accountPendingDeletion = nil
                    Task { await store.deleteAccount(account.id) }
                }
            }
            Button("Cancel", role: .cancel) { accountPendingDeletion = nil }
        } message: {
            Text("This removes only the selected account and its cached usage data.")
        }
    }

    @ViewBuilder
    private func accountRow(_ account: ProviderAccount) -> some View {
        let state = store.states[account.id]
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(accountName(account))
                Text(state?.isConnected == true ? String(localized: "Connected", locale: locale) : String(localized: "Not connected", locale: locale))
                    .font(.caption)
                    .foregroundStyle(state?.isConnected == true ? .green : .secondary)
            }
            Spacer()
            if state?.isConnected == false {
                Button("Reconnect") {
                    Task { await store.reconnect(account.id) }
                }
            }
            Button(role: .destructive) {
                accountPendingDeletion = account
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete account")
        }
    }

    @ViewBuilder
    private func selectedAccountPicker(_ provider: AIProvider) -> some View {
        let providerAccounts = store.accounts(for: provider)
        if let selected = store.selectedAccountIdentifier(for: provider), !providerAccounts.isEmpty {
            Picker(
                String(
                    localized: "provider.display.account",
                    defaultValue: "\(provider.displayName) Widget & Watch account",
                    locale: locale
                ),
                selection: Binding(
                    get: { store.selectedAccountIdentifier(for: provider) ?? selected },
                    set: { store.selectAccount($0, for: provider) }
                )
            ) {
                ForEach(providerAccounts) { account in
                    Text(accountName(account)).tag(account.id)
                }
            }
        }
    }

    private func accountName(_ account: ProviderAccount) -> String {
        account.identityLabel ?? String(
            localized: "account.number",
            defaultValue: "Account \(account.ordinal)",
            locale: locale
        )
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
