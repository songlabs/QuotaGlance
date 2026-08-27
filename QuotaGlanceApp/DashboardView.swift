import QuotaGlanceCore
import SwiftUI

struct DashboardView: View {
    @Bindable var store: DashboardStore
    let runsStartupTasks: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale

    init(store: DashboardStore, runsStartupTasks: Bool = true) {
        self.store = store
        self.runsStartupTasks = runsStartupTasks
    }

    var body: some View {
        NavigationStack {
            ZStack {
                QuotaGlanceTheme.appBackground.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: QuotaGlanceTheme.sectionSpacing) {
                        ForEach(AIProvider.allCases) { provider in
                            ProviderGroup(store: store, provider: provider)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .refreshable { await store.refreshAll(force: true) }
            }
            .navigationTitle("QuotaGlance")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    QuotaGlanceBrandIcon(size: 24)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string("Settings", locale: locale), systemImage: "gearshape") {
                        store.isShowingUpgrade = false
                        store.isShowingSettings = true
                    }
                    .accessibilityLabel(AppLocalization.string("Settings", locale: locale))
                }
            }
        }
        .tint(QuotaGlanceTheme.brandAccent)
        .sheet(isPresented: $store.isShowingSettings) {
            SettingsView(store: store)
        }
        .sheet(isPresented: $store.isShowingUpgrade) {
            UpgradeView(store: store)
        }
        .task {
            guard runsStartupTasks else { return }
            let previousAccessLevel = store.accessLevel
            await store.purchaseManager.start()
            await store.refreshAccess(previousAccessLevel: previousAccessLevel)
            await store.backfillAccountIdentityLabels()
            await store.refreshAll(force: false)
        }
        .task(id: store.accessLevel) {
            guard runsStartupTasks else { return }
            if store.accessLevel == .trial {
                let remaining = store.purchaseManager.trialTimeRemaining
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                    await store.refreshAccess()
                }
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard runsStartupTasks, newValue == .active else { return }
            Task {
                await store.refreshAccess()
                await store.refreshAll(force: false)
            }
        }
    }
}

private struct ProviderGroup: View {
    @Bindable var store: DashboardStore
    let provider: AIProvider
    @Environment(\.locale) private var locale

    private var accounts: [ProviderAccount] { store.accounts(for: provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                providerLabel
                    .font(.headline)
                    .foregroundStyle(provider.accent)
                Spacer()
                Button {
                    if store.canAddAccount { Task { await store.addAccount(provider) } }
                    else { store.requirePro() }
                } label: {
                    Label(AppLocalization.string("Add account", locale: locale), systemImage: "plus")
                }
                .font(.subheadline.weight(.medium))
                .disabled(store.connectingProviders.contains(provider))
            }

            if accounts.isEmpty {
                EmptyProviderCard(
                    provider: provider,
                    isConnecting: store.connectingProviders.contains(provider),
                    errorMessage: store.providerErrors[provider]?.message(locale: locale),
                    connect: { await store.addAccount(provider) }
                )
            } else {
                ForEach(accounts) { account in
                    if let state = store.states[account.id] {
                        AccountSection(
                            state: state,
                            showsWeekly: store.purchaseManager.hasProFeatures,
                            refresh: { await store.refresh(account.id) },
                            reconnect: { await store.reconnect(account.id) }
                        )
                    }
                }

                if let error = store.providerErrors[provider] {
                    Label(error.message(locale: locale), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(QuotaGlanceTheme.attention)
                }
            }
        }
    }

    @ViewBuilder
    private var providerLabel: some View {
        Label(
            provider.displayName,
            systemImage: provider == .codex ? "terminal" : "sparkles"
        )
    }
}

private struct AccountSection: View {
    let state: ProviderPresentation
    let showsWeekly: Bool
    let refresh: () async -> Void
    let reconnect: () async -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let snapshot = state.snapshot {
                UsageCard(
                    snapshot: snapshot,
                    accountName: accountName,
                    showsWeekly: showsWeekly,
                    isRefreshing: state.isRefreshing,
                    errorMessage: state.error?.message(locale: locale),
                    refresh: refresh,
                    reconnect: state.isConnected ? nil : reconnect
                )
            } else if state.isConnected, state.isRefreshing {
                LoadingCard(provider: state.provider, accountName: accountName)
            } else {
                AccountStatusCard(
                    provider: state.provider,
                    accountName: accountName,
                    isConnected: state.isConnected,
                    isWorking: state.isRefreshing,
                    errorMessage: state.error?.message(locale: locale),
                    action: state.isConnected ? refresh : reconnect
                )
            }
        }
    }

    private var accountName: String {
        state.account.displayName(fallback: AppLocalization.string(
            "account.number",
            defaultValue: "Account %lld",
            locale: locale,
            arguments: [state.account.ordinal]
        ))
    }
}

private struct EmptyProviderCard: View {
    let provider: AIProvider
    let isConnecting: Bool
    let errorMessage: String?
    let connect: () async -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(provider == .codex
                 ? AppLocalization.string("Track your Codex usage and reset time.", locale: locale)
                 : AppLocalization.string("Track your Claude Code usage and reset time.", locale: locale))
                .foregroundStyle(QuotaGlanceTheme.secondaryText)
            Button {
                Task { await connect() }
            } label: {
                HStack {
                    if isConnecting { ProgressView().tint(.black) }
                    Text(isConnecting
                         ? AppLocalization.string("Connecting…", locale: locale)
                         : AppLocalization.string("Add account", locale: locale))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(provider.accent)
            .foregroundStyle(.black)
            .disabled(isConnecting)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(QuotaGlanceTheme.attention)
            }
        }
        .padding(QuotaGlanceTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .quotaCardSurface()
    }
}

private struct AccountStatusCard: View {
    let provider: AIProvider
    let accountName: String
    let isConnected: Bool
    let isWorking: Bool
    let errorMessage: String?
    let action: () async -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(accountName).font(.headline)
            Text(isConnected
                 ? AppLocalization.string("Connected, but no usage data has been received yet.", locale: locale)
                 : AppLocalization.string("Session expired. Connect again.", locale: locale))
                .foregroundStyle(QuotaGlanceTheme.secondaryText)
            Button {
                Task { await action() }
            } label: {
                HStack {
                    if isWorking { ProgressView().tint(.black) }
                    Text(isConnected
                         ? AppLocalization.string("Retry refresh", locale: locale)
                         : AppLocalization.string("Reconnect", locale: locale))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(provider.accent)
            .foregroundStyle(.black)
            .disabled(isWorking)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(QuotaGlanceTheme.attention)
            }
        }
        .padding(QuotaGlanceTheme.cardPadding)
        .quotaCardSurface()
    }
}

private struct LoadingCard: View {
    @Environment(\.locale) private var locale
    let provider: AIProvider
    let accountName: String

    var body: some View {
        HStack(spacing: 14) {
            ProgressView().tint(provider.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(accountName).font(.headline)
                Text(AppLocalization.string("Loading usage…", locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(QuotaGlanceTheme.secondaryText)
            }
            Spacer()
        }
        .padding(QuotaGlanceTheme.cardPadding)
        .quotaCardSurface()
    }
}

#Preview("Disconnected") {
    DashboardView(store: PreviewFactory.dashboard(states: []))
}

#Preview("Both connected") {
    DashboardView(store: PreviewFactory.dashboard(states: PreviewFactory.normalStates))
}

#Preview("Low remaining") {
    DashboardView(store: PreviewFactory.dashboard(states: PreviewFactory.lowStates))
}

#Preview("Cached data") {
    DashboardView(store: PreviewFactory.dashboard(states: PreviewFactory.cachedStates))
}

#Preview("API error") {
    DashboardView(store: PreviewFactory.dashboard(states: PreviewFactory.errorStates))
}

#Preview("Loading") {
    DashboardView(store: PreviewFactory.dashboard(states: PreviewFactory.loadingStates))
}
