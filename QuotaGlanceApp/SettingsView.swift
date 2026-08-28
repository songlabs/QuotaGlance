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
                ScrollView {
                    VStack(spacing: 18) {
                        settingsHeader
                        generalSection
                        refreshSection
                        accountsSection
                        displaySection.id("display")
                        watchSection.id("watch")
                        informationSection
                        proSection
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
                }
                .background(QuotaGlanceTheme.appBackground.ignoresSafeArea())
                .onAppear {
                    guard let initialScrollTarget else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(initialScrollTarget, anchor: .top)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
            Button(AppLocalization.string("Cancel", locale: locale), role: .cancel) {
                accountPendingRename = nil
            }
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
            Button(AppLocalization.string("Cancel", locale: locale), role: .cancel) {
                accountPendingDeletion = nil
            }
        } message: {
            Text(AppLocalization.string(
                "This removes only the selected account and its cached usage data.",
                locale: locale
            ))
        }
    }

    private var settingsHeader: some View {
        ZStack {
            Text(AppLocalization.string("Settings", locale: locale))
                .font(.title3.bold())
                .foregroundStyle(QuotaGlanceTheme.primaryText)

            HStack {
                QuotaGlanceBrandIcon(size: 36)
                    .frame(width: 48, height: 48)
                    .background(
                        QuotaGlanceTheme.secondarySurface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(QuotaGlanceTheme.border)
                    }
                Spacer()
                Button(AppLocalization.string("Done", locale: locale)) {
                    dismiss()
                }
                .font(.headline)
                .foregroundStyle(QuotaGlanceTheme.brandAccent)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(QuotaGlanceTheme.secondarySurface, in: Capsule())
                .overlay { Capsule().stroke(QuotaGlanceTheme.border) }
            }
        }
        .frame(minHeight: 48)
    }

    private var generalSection: some View {
        settingsSection(title: AppLocalization.string("General", locale: locale)) {
            settingsRow(icon: "globe", title: AppLocalization.string("Language", locale: locale)) {
                Picker("", selection: $store.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName(locale: locale)).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(QuotaGlanceTheme.brandAccent)
                .fixedSize(horizontal: true, vertical: false)
            }
            settingsDivider()
            settingsRow(icon: "terminal", title: AppLocalization.string("Default provider", locale: locale)) {
                Picker("", selection: Binding(
                    get: { store.defaultProvider },
                    set: { store.defaultProvider = $0 }
                )) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(QuotaGlanceTheme.brandAccent)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.string("Refresh", locale: locale)).settingsSectionTitle()
            VStack(spacing: 0) {
                settingsRow(
                    icon: "clock.arrow.2.circlepath",
                    title: AppLocalization.string("Automatic refresh interval", locale: locale)
                ) {
                    Picker("", selection: Binding(
                        get: { store.effectiveRefreshInterval },
                        set: { store.updateRefreshInterval($0) }
                    )) {
                        ForEach(AutomaticRefreshInterval.allCases) { interval in
                            Text(refreshIntervalTitle(interval)).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(QuotaGlanceTheme.brandAccent)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(!store.purchaseManager.hasProFeatures)
                    .overlay {
                        if !store.purchaseManager.hasProFeatures {
                            Color.clear.contentShape(Rectangle()).onTapGesture { isShowingUpgrade = true }
                        }
                    }
                }
            }
            .settingsCardSurface()

            VStack(alignment: .leading, spacing: 4) {
                if !store.purchaseManager.hasProFeatures {
                    Text(AppLocalization.string("Free refresh interval is fixed at 4 hours.", locale: locale))
                }
                Text(AppLocalization.string(
                    "Background refresh timing is determined by iOS and may occur later than the selected interval.",
                    locale: locale
                ))
            }
            .font(.caption)
            .foregroundStyle(QuotaGlanceTheme.secondaryText)
            .padding(.horizontal, 12)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountsSection: some View {
        settingsSection(title: AppLocalization.string("Accounts", locale: locale)) {
            ForEach(AIProvider.allCases) { provider in
                if provider != AIProvider.allCases.first { settingsDivider(inset: 16) }
                providerAccountHeader(provider)
                ForEach(store.accounts(for: provider)) { account in
                    settingsDivider(inset: 58)
                    accountRow(account)
                }
            }
        }
    }

    private var displaySection: some View {
        settingsSection(title: AppLocalization.string("Display", locale: locale)) {
            ForEach(providersWithAccounts) { provider in
                if let selected = store.selectedAccountIdentifier(for: provider),
                   !store.accounts(for: provider).isEmpty {
                    if provider != providersWithAccounts.first { settingsDivider(inset: 58) }
                    settingsRow(
                        icon: provider == .codex ? "terminal" : "sparkles",
                        iconColor: provider.accent,
                        title: AppLocalization.string(
                            "provider.widget.account",
                            defaultValue: "%@ Widget account",
                            locale: locale,
                            arguments: [provider.displayName]
                        )
                    ) {
                        Picker("", selection: Binding(
                            get: { store.selectedAccountIdentifier(for: provider) ?? selected },
                            set: { store.selectAccount($0, for: provider) }
                        )) {
                            ForEach(store.accounts(for: provider)) { account in
                                Text(accountName(account)).tag(account.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(QuotaGlanceTheme.brandAccent)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }

            if AIProvider.allCases.contains(where: { !store.accounts(for: $0).isEmpty }) {
                settingsDivider(inset: 58)
            }

            settingsRow(icon: "applewatch", title: AppLocalization.string("Widget & Watch quota", locale: locale)) {
                Picker("", selection: Binding(
                    get: { store.effectiveDisplayLimit },
                    set: { store.updateDisplayLimit($0) }
                )) {
                    Text(AppLocalization.string("5 hours", locale: locale)).tag(QuotaDisplayLimit.fiveHour)
                    Text(AppLocalization.string("Weekly", locale: locale)).tag(QuotaDisplayLimit.weekly)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(QuotaGlanceTheme.brandAccent)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(!store.purchaseManager.hasProFeatures)
                .overlay {
                    if !store.purchaseManager.hasProFeatures {
                        Color.clear.contentShape(Rectangle()).onTapGesture { isShowingUpgrade = true }
                    }
                }
            }
        }
    }

    private var watchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.string("Apple Watch", locale: locale)).settingsSectionTitle()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "applewatch")
                        .font(.title3)
                        .foregroundStyle(QuotaGlanceTheme.brandAccent)
                        .frame(width: 30)
                    Text(AppLocalization.string("Apple Watch display accounts", locale: locale))
                        .foregroundStyle(QuotaGlanceTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Text(verbatim: "\(store.effectiveWatchAccountIdentifiers.count)/\(WatchAccountSelection.maximumCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuotaGlanceTheme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(QuotaGlanceTheme.secondarySurface, in: Capsule())
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuotaGlanceTheme.secondaryText)
                        .accessibilityHidden(true)
                }

                Text(AppLocalization.string(
                    store.purchaseManager.hasProFeatures
                        ? "Choose up to 2 accounts for Apple Watch."
                        : "Free uses the first account. Trial and Pro can choose up to 2 accounts.",
                    locale: locale
                ))
                .font(.caption)
                .foregroundStyle(QuotaGlanceTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: watchGridColumns,
                    spacing: 8
                ) {
                    ForEach(watchAccounts) { account in
                        watchAccountButton(account)
                    }
                }
            }
            .padding(16)
            .settingsCardSurface()
        }
    }

    private var informationSection: some View {
        settingsSection(title: AppLocalization.string("About", locale: locale)) {
            linkRow(
                title: AppLocalization.string("Privacy", locale: locale),
                icon: "checkmark.shield",
                destination: URL(string: "https://songlabs.github.io/QuotaGlance/privacy/")!
            )
            settingsDivider(inset: 58)
            linkRow(
                title: AppLocalization.string("Terms of Use", locale: locale),
                icon: "doc.text",
                destination: URL(string: "https://songlabs.github.io/QuotaGlance/terms/")!
            )
            settingsDivider(inset: 58)
            linkRow(
                title: AppLocalization.string("Support", locale: locale),
                icon: "questionmark.circle",
                destination: URL(string: "https://songlabs.github.io/QuotaGlance/support/")!
            )
            settingsDivider(inset: 58)
            settingsRow(icon: "key", title: AppLocalization.string("Privacy", locale: locale)) {
                Text(AppLocalization.string("Credentials stay in Keychain", locale: locale))
                    .font(.caption)
                    .foregroundStyle(QuotaGlanceTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            settingsDivider(inset: 58)
            settingsRow(icon: "info.circle", title: AppLocalization.string("Version", locale: locale)) {
                Text(version).foregroundStyle(QuotaGlanceTheme.secondaryText)
            }
        }
    }

    private var proSection: some View {
        settingsSection(title: AppLocalization.string("Pro", locale: locale)) {
            Button {
                if SettingsUpgradeRouting.shouldPresentMembership(for: store.accessLevel) {
                    isShowingUpgrade = true
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(QuotaGlanceTheme.brandAccent)
                        .frame(width: 30)
                    Text(accessTitle).foregroundStyle(QuotaGlanceTheme.primaryText)
                    Spacer()
                    Text(store.accessLevel == .pro
                         ? AppLocalization.string("Lifetime Unlock", locale: locale)
                         : AppLocalization.string("Upgrade to Pro", locale: locale))
                        .foregroundStyle(QuotaGlanceTheme.brandAccent)
                    if store.accessLevel != .pro {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(QuotaGlanceTheme.secondaryText)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).settingsSectionTitle()
            VStack(spacing: 0) { content() }
                .settingsCardSurface()
        }
    }

    private func settingsRow<Trailing: View>(
        icon: String,
        iconColor: Color = QuotaGlanceTheme.brandAccent,
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 30)
            Text(title)
                .foregroundStyle(QuotaGlanceTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
    }

    private func settingsDivider(inset: CGFloat = 58) -> some View {
        Divider()
            .overlay(QuotaGlanceTheme.border)
            .padding(.leading, inset)
            .padding(.trailing, 16)
    }

    private func providerAccountHeader(_ provider: AIProvider) -> some View {
        HStack(spacing: 12) {
            Image(systemName: provider == .codex ? "terminal" : "sparkles")
                .font(.title3)
                .foregroundStyle(provider.accent)
                .frame(width: 30)
            Text(providerAccountsTitle(provider))
                .font(.headline)
                .foregroundStyle(provider.accent)
            Spacer()
            Button {
                if store.canAddAccount {
                    Task { await store.addAccount(provider) }
                } else {
                    isShowingUpgrade = true
                }
            } label: {
                Group {
                    if store.connectingProviders.contains(provider) {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "plus").font(.title2.weight(.regular))
                    }
                }
                .foregroundStyle(provider.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.connectingProviders.contains(provider))
            .accessibilityLabel(AppLocalization.string("Add account", locale: locale))
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minHeight: 56)
    }

    private func accountRow(_ account: ProviderAccount) -> some View {
        let state = store.states[account.id]
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(account.provider.accent.opacity(0.12))
                Circle().stroke(account.provider.accent.opacity(0.35), lineWidth: 1)
                Image(systemName: "person.fill")
                    .font(.subheadline)
                    .foregroundStyle(account.provider.accent)
            }
            .frame(width: 32, height: 32)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(accountName(account))
                    .foregroundStyle(QuotaGlanceTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(state?.isConnected == true
                     ? AppLocalization.string("Connected", locale: locale)
                     : AppLocalization.string("Not connected", locale: locale))
                    .font(.caption)
                    .foregroundStyle(state?.isConnected == true
                                     ? QuotaGlanceTheme.brandAccent
                                     : QuotaGlanceTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
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
                    .foregroundStyle(QuotaGlanceTheme.primaryText)
                    .frame(width: 34, height: 34)
                    .background(QuotaGlanceTheme.secondarySurface.opacity(0.7), in: Circle())
                    .overlay { Circle().stroke(QuotaGlanceTheme.border) }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(AppLocalization.string("Account actions", locale: locale))
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minHeight: 56)
    }

    private func watchAccountButton(_ account: ProviderAccount) -> some View {
        let isSelected = store.isSelectedForWatch(account.id)
        return Button {
            if store.purchaseManager.hasProFeatures {
                store.toggleWatchSelection(account.id)
            } else {
                isShowingUpgrade = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected
                                     ? QuotaGlanceTheme.brandAccent
                                     : QuotaGlanceTheme.secondaryText)
                Image(systemName: account.provider == .codex ? "terminal" : "sparkles")
                    .foregroundStyle(account.provider.accent)
                Text(verbatim: "\(account.provider.displayName) / \(accountName(account))")
                    .foregroundStyle(QuotaGlanceTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .font(.caption2)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 42)
            .background(QuotaGlanceTheme.secondarySurface.opacity(0.45), in: Capsule())
            .overlay { Capsule().stroke(QuotaGlanceTheme.border) }
        }
        .buttonStyle(.plain)
        .disabled(store.purchaseManager.hasProFeatures && !store.canToggleWatchSelection(account.id))
    }

    private func linkRow(title: String, icon: String, destination: URL) -> some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(QuotaGlanceTheme.brandAccent)
                    .frame(width: 30)
                Text(title).foregroundStyle(QuotaGlanceTheme.primaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuotaGlanceTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
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

    private var providersWithAccounts: [AIProvider] {
        AIProvider.allCases.filter { !store.accounts(for: $0).isEmpty }
    }

    private var watchGridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: min(max(watchAccounts.count, 1), 3)
        )
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

private extension View {
    func settingsCardSurface() -> some View {
        background(QuotaGlanceTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(QuotaGlanceTheme.border)
            }
    }

    func settingsSectionTitle() -> some View {
        font(.subheadline)
            .foregroundStyle(QuotaGlanceTheme.secondaryText)
            .padding(.horizontal, 12)
    }
}
