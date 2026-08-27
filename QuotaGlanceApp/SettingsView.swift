import QuotaGlanceCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: DashboardStore
    let initialScrollTarget: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var accountPendingDeletion: ProviderAccount?
    @State private var accountPendingRename: ProviderAccount?
    @State private var accountNameDraft = ""
    @State private var isShowingUpgrade = false

    init(store: DashboardStore, initialScrollTarget: String? = nil) {
        self.store = store
        self.initialScrollTarget = initialScrollTarget
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                Section {
                    Button {
                        if SettingsUpgradeRouting.shouldPresentMembership(for: store.accessLevel) {
                            isShowingUpgrade = true
                        }
                    } label: {
                        LabeledContent {
                            Text(store.accessLevel == .pro
                                 ? AppLocalization.string("Lifetime Unlock", locale: locale)
                                 : AppLocalization.string("Upgrade to Pro", locale: locale))
                        } label: {
                            Label(accessTitle, systemImage: "crown.fill")
                        }
                    }
                }
                .listRowBackground(QuotaGlanceTheme.cardBackground)
                Section(AppLocalization.string("Language", locale: locale)) {
                    Picker(AppLocalization.string("Language", locale: locale), selection: $store.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName(locale: locale)).tag(language)
                        }
                    }
                }
                .listRowBackground(QuotaGlanceTheme.cardBackground)

                Section {
                    HStack(spacing: 16) {
                        Picker(AppLocalization.string("Time", locale: locale), selection: Binding(
                            get: { store.effectiveRefreshInterval.value },
                            set: { store.updateRefreshInterval(store.refreshInterval.replacingValue($0)) }
                        )) {
                            ForEach(refreshIntervalValues, id: \.self) { value in
                                Text(verbatim: "\(value)").tag(value)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker(AppLocalization.string("Unit", locale: locale), selection: Binding(
                            get: { store.effectiveRefreshInterval.unit },
                            set: { store.updateRefreshInterval(store.refreshInterval.replacingUnit($0)) }
                        )) {
                            Text(AppLocalization.string("Minutes", locale: locale))
                                .tag(RefreshIntervalUnit.minute)
                            Text(AppLocalization.string("Hours", locale: locale))
                                .tag(RefreshIntervalUnit.hour)
                        }
                        .pickerStyle(.menu)
                    }
                    .disabled(!store.purchaseManager.hasProFeatures)
                    .overlay {
                        if !store.purchaseManager.hasProFeatures {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { isShowingUpgrade = true }
                        }
                    }
                } header: {
                    Text(AppLocalization.string("Automatic refresh interval", locale: locale))
                } footer: {
                    Text(AppLocalization.string(
                        store.purchaseManager.hasProFeatures
                            ? "0 = Automatic refresh off"
                            : "Free refresh interval is fixed at 60 minutes",
                        locale: locale
                    ))
                }
                .listRowBackground(QuotaGlanceTheme.cardBackground)

                ForEach(AIProvider.allCases) { provider in
                    Section(provider.displayName) {
                        ForEach(store.accounts(for: provider)) { account in
                            accountRow(account)
                        }
                        Button {
                            if store.canAddAccount { Task { await store.addAccount(provider) } }
                            else { isShowingUpgrade = true }
                        } label: {
                            Label(AppLocalization.string("Add account", locale: locale), systemImage: "plus")
                        }
                        .disabled(store.connectingProviders.contains(provider))
                    }
                    .listRowBackground(QuotaGlanceTheme.cardBackground)
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

                    Picker(AppLocalization.string("Widget & Watch quota", locale: locale), selection: Binding(
                        get: { store.displayLimit },
                        set: { store.displayLimit = $0 }
                    )) {
                        Text(AppLocalization.string("5 hours", locale: locale)).tag(QuotaDisplayLimit.fiveHour)
                        Text(AppLocalization.string("Weekly", locale: locale)).tag(QuotaDisplayLimit.weekly)
                    }
                    .disabled(!store.purchaseManager.hasProFeatures)
                    .overlay {
                        if !store.purchaseManager.hasProFeatures {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { isShowingUpgrade = true }
                        }
                    }
                }
                .listRowBackground(QuotaGlanceTheme.cardBackground)
                .id("display")

                Section {
                    ForEach(watchAccounts) { account in
                        Button {
                            if store.purchaseManager.hasProFeatures { store.toggleWatchSelection(account.id) }
                            else { isShowingUpgrade = true }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: account.provider == .codex ? "terminal" : "sparkles")
                                    .foregroundStyle(account.provider.accent)
                                Text(verbatim: "\(account.provider.displayName) / \(accountName(account))")
                                    .foregroundStyle(QuotaGlanceTheme.primaryText)
                                Spacer()
                                if store.isSelectedForWatch(account.id) {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(QuotaGlanceTheme.brandAccent)
                                }
                            }
                        }
                        .disabled(store.purchaseManager.hasProFeatures && !store.canToggleWatchSelection(account.id))
                    }
                } header: {
                    Text(AppLocalization.string("Apple Watch display accounts", locale: locale))
                } footer: {
                    Text(AppLocalization.string("Choose up to 2 accounts for Apple Watch.", locale: locale))
                }
                .listRowBackground(QuotaGlanceTheme.cardBackground)
                .id("watch")

                Section(AppLocalization.string("About", locale: locale)) {
                    LabeledContent(AppLocalization.string("Privacy", locale: locale), value: AppLocalization.string("Credentials stay in Keychain", locale: locale))
                    LabeledContent(AppLocalization.string("Version", locale: locale), value: version)
                }
                .listRowBackground(QuotaGlanceTheme.cardBackground)
                }
                .scrollContentBackground(.hidden)
                .background(QuotaGlanceTheme.appBackground)
                .navigationTitle(AppLocalization.string("Settings", locale: locale))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppLocalization.string("Done", locale: locale)) { dismiss() }
                    }
                }
                .onAppear {
                    guard let initialScrollTarget else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(initialScrollTarget, anchor: .top)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(QuotaGlanceTheme.brandAccent)
        .sheet(isPresented: $isShowingUpgrade) {
            UpgradeView(store: store)
        }
        .onDisappear {
            store.isShowingUpgrade = false
        }
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

    private var accessTitle: String {
        switch store.accessLevel {
        case .trial: AppLocalization.string("7-Day Free Trial", locale: locale)
        case .free: AppLocalization.string("Free", locale: locale)
        case .pro: AppLocalization.string("Pro", locale: locale)
        }
    }

    private var refreshIntervalValues: [Int] {
        let interval = store.effectiveRefreshInterval
        let standardValues = Array(interval.unit.valueRange)
        guard !standardValues.contains(interval.value) else { return standardValues }
        return (standardValues + [interval.value]).sorted()
    }

    @ViewBuilder
    private func accountRow(_ account: ProviderAccount) -> some View {
        let state = store.states[account.id]
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(accountName(account))
                Text(state?.isConnected == true ? AppLocalization.string("Connected", locale: locale) : AppLocalization.string("Not connected", locale: locale))
                    .font(.caption)
                    .foregroundStyle(
                        state?.isConnected == true
                            ? QuotaGlanceTheme.brandAccent
                            : QuotaGlanceTheme.secondaryText
                    )
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
                    "provider.widget.account",
                    defaultValue: "%@ Widget account",
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

    private var watchAccounts: [ProviderAccount] {
        AIProvider.allCases.flatMap { store.accounts(for: $0) }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
