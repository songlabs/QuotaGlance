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
                Section(AppLocalization.string("Pro", locale: locale)) {
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

                Section(AppLocalization.string("General", locale: locale)) {
                    Picker(AppLocalization.string("Language", locale: locale), selection: $store.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName(locale: locale)).tag(language)
                        }
                    }

                    Picker(AppLocalization.string("Default provider", locale: locale), selection: Binding(
                        get: { store.defaultProvider },
                        set: { store.defaultProvider = $0 }
                    )) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                }
                .listRowBackground(QuotaGlanceTheme.cardBackground)

                Section {
                    Picker(AppLocalization.string("Automatic refresh interval", locale: locale), selection: Binding(
                        get: { store.effectiveRefreshInterval },
                        set: { store.updateRefreshInterval($0) }
                    )) {
                        ForEach(AutomaticRefreshInterval.allCases) { interval in
                            Text(refreshIntervalTitle(interval)).tag(interval)
                        }
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
                    Text(AppLocalization.string("Refresh", locale: locale))
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if !store.purchaseManager.hasProFeatures {
                            Text(AppLocalization.string("Free refresh interval is fixed at 4 hours.", locale: locale))
                        }
                        Text(AppLocalization.string(
                            "Background refresh timing is determined by iOS and may occur later than the selected interval.",
                            locale: locale
                        ))
                    }
                }
                .listRowBackground(QuotaGlanceTheme.cardBackground)

                Section(AppLocalization.string("Accounts", locale: locale)) {
                    ForEach(AIProvider.allCases) { provider in
                        Label(
                            providerAccountsTitle(provider),
                            systemImage: provider == .codex ? "terminal" : "sparkles"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(provider.accent)

                        ForEach(store.accounts(for: provider)) { account in
                            accountRow(account)
                        }
                        Button {
                            if store.canAddAccount { Task { await store.addAccount(provider) } }
                            else { isShowingUpgrade = true }
                        } label: {
                            Label(AppLocalization.string("Add account", locale: locale), systemImage: "plus")
                        }
                        .tint(provider.accent)
                        .disabled(store.connectingProviders.contains(provider))
                    }
                }
                .listRowBackground(QuotaGlanceTheme.cardBackground)

                Section(AppLocalization.string("Display", locale: locale)) {
                    ForEach(AIProvider.allCases) { provider in
                        selectedAccountPicker(provider)
                    }

                    Picker(AppLocalization.string("Widget & Watch quota", locale: locale), selection: Binding(
                        get: { store.effectiveDisplayLimit },
                        set: { store.updateDisplayLimit($0) }
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
                    HStack {
                        Label(AppLocalization.string("Apple Watch display accounts", locale: locale), systemImage: "applewatch")
                        Spacer()
                        Text(verbatim: "\(store.effectiveWatchAccountIdentifiers.count)/\(WatchAccountSelection.maximumCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(QuotaGlanceTheme.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(QuotaGlanceTheme.secondarySurface, in: Capsule())
                    }

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
                    Text(AppLocalization.string("Apple Watch", locale: locale))
                } footer: {
                    Text(AppLocalization.string(
                        store.purchaseManager.hasProFeatures
                            ? "Choose up to 2 accounts for Apple Watch."
                            : "Free uses the first account. Trial and Pro can choose up to 2 accounts.",
                        locale: locale
                    ))
                }
                .listRowBackground(QuotaGlanceTheme.cardBackground)
                .id("watch")

                Section(AppLocalization.string("About", locale: locale)) {
                    LabeledContent(AppLocalization.string("Privacy", locale: locale), value: AppLocalization.string("Credentials stay in Keychain", locale: locale))
                    Link(
                        AppLocalization.string("Privacy Policy", locale: locale),
                        destination: URL(string: "https://songlabs.github.io/QuotaGlance/privacy/")!
                    )
                    Link(
                        AppLocalization.string("Terms of Use", locale: locale),
                        destination: URL(string: "https://songlabs.github.io/QuotaGlance/terms/")!
                    )
                    Link(
                        AppLocalization.string("Support", locale: locale),
                        destination: URL(string: "https://songlabs.github.io/QuotaGlance/support/")!
                    )
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

    private func refreshIntervalTitle(_ interval: AutomaticRefreshInterval) -> String {
        switch interval {
        case .disabled: AppLocalization.string("Off", locale: locale)
        case .fifteenMinutes: AppLocalization.string("15 Minutes", locale: locale)
        case .thirtyMinutes: AppLocalization.string("30 Minutes", locale: locale)
        case .oneHour: AppLocalization.string("1 Hour", locale: locale)
        case .twoHours: AppLocalization.string("2 Hours", locale: locale)
        case .fourHours: AppLocalization.string("4 Hours", locale: locale)
        }
    }

    private func providerAccountsTitle(_ provider: AIProvider) -> String {
        AppLocalization.string(
            "provider.accounts",
            defaultValue: "%@ Accounts",
            locale: locale,
            arguments: [provider.displayName]
        )
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
            Menu {
                Button(AppLocalization.string("Rename account", locale: locale), systemImage: "pencil") {
                    accountNameDraft = account.customDisplayName ?? ""
                    accountPendingRename = account
                }
                if state?.isConnected == false {
                    Button(AppLocalization.string("Reconnect", locale: locale), systemImage: "arrow.clockwise") {
                        Task { await store.reconnect(account.id) }
                    }
                }
                Divider()
                Button(role: .destructive) {
                    accountPendingDeletion = account
                } label: {
                    Label(AppLocalization.string("Delete account", locale: locale), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel(AppLocalization.string("Account actions", locale: locale))
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
