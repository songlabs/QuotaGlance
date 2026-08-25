import QuotaGlanceCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var accountPendingDeletion: ProviderAccount?
    @State private var accountPendingRename: ProviderAccount?
    @State private var accountNameDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.string("Language", locale: locale)) {
                    Picker(AppLocalization.string("Language", locale: locale), selection: $store.appLanguage) {
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
                            Label(AppLocalization.string("Add account", locale: locale), systemImage: "plus")
                        }
                        .disabled(store.connectingProviders.contains(provider))
                    }
                }

                Section(AppLocalization.string("Display", locale: locale)) {
                    Picker(AppLocalization.string("Default provider", locale: locale), selection: Binding(
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

                Section(AppLocalization.string("About", locale: locale)) {
                    LabeledContent(AppLocalization.string("Privacy", locale: locale), value: AppLocalization.string("Credentials stay in Keychain", locale: locale))
                    LabeledContent(AppLocalization.string("Version", locale: locale), value: version)
                }
            }
            .navigationTitle(AppLocalization.string("Settings", locale: locale))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Done", locale: locale)) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert(AppLocalization.string("Rename account", locale: locale), isPresented: Binding(
            get: { accountPendingRename != nil },
            set: { if !$0 { accountPendingRename = nil } }
        )) {
            TextField(AppLocalization.string("Account name", locale: locale), text: $accountNameDraft)
            Button(AppLocalization.string("Save", locale: locale)) {
                if let account = accountPendingRename {
                    store.renameAccount(account.id, name: accountNameDraft)
                }
                accountPendingRename = nil
            }
            Button(AppLocalization.string("Cancel", locale: locale), role: .cancel) { accountPendingRename = nil }
        } message: {
            Text(AppLocalization.string("Leave blank to use the account identity.", locale: locale))
        }
        .confirmationDialog(
            AppLocalization.string("Delete account?", locale: locale),
            isPresented: Binding(
                get: { accountPendingDeletion != nil },
                set: { if !$0 { accountPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let account = accountPendingDeletion {
                Button(AppLocalization.string("Delete account", locale: locale), role: .destructive) {
                    accountPendingDeletion = nil
                    Task { await store.deleteAccount(account.id) }
                }
            }
            Button(AppLocalization.string("Cancel", locale: locale), role: .cancel) { accountPendingDeletion = nil }
        } message: {
            Text(AppLocalization.string("This removes only the selected account and its cached usage data.", locale: locale))
        }
    }

    @ViewBuilder
    private func accountRow(_ account: ProviderAccount) -> some View {
        let state = store.states[account.id]
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(accountName(account))
                Text(state?.isConnected == true ? AppLocalization.string("Connected", locale: locale) : AppLocalization.string("Not connected", locale: locale))
                    .font(.caption)
                    .foregroundStyle(state?.isConnected == true ? .green : .secondary)
            }
            Spacer()
            if state?.isConnected == false {
                Button(AppLocalization.string("Reconnect", locale: locale)) {
                    Task { await store.reconnect(account.id) }
                }
            }
            Button(role: .destructive) {
                accountPendingDeletion = account
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel(AppLocalization.string("Delete account", locale: locale))
        }
        .contextMenu {
            Button(AppLocalization.string("Rename", locale: locale), systemImage: "pencil") {
                accountNameDraft = account.customDisplayName ?? ""
                accountPendingRename = account
            }
        }
    }

    @ViewBuilder
    private func selectedAccountPicker(_ provider: AIProvider) -> some View {
        let providerAccounts = store.accounts(for: provider)
        if let selected = store.selectedAccountIdentifier(for: provider), !providerAccounts.isEmpty {
            Picker(
                AppLocalization.string(
                    "provider.display.account",
                    defaultValue: "%@ Widget & Watch account",
                    locale: locale,
                    arguments: [provider.displayName]
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
        account.displayName(fallback: AppLocalization.string(
            "account.number",
            defaultValue: "Account %lld",
            locale: locale,
            arguments: [account.ordinal]
        ))
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
