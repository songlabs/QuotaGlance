import QuotaGlanceCore
import SwiftUI

struct DashboardView: View {
    @Bindable var store: DashboardStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.025, green: 0.04, blue: 0.075).ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 18) {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        store.isShowingSettings = true
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .tint(.white)
        .sheet(isPresented: $store.isShowingSettings) {
            SettingsView(store: store)
        }
        .task { await store.refreshAll(force: false) }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await store.refreshAll(force: false) }
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
                Label(provider.displayName, systemImage: provider == .codex ? "sparkles" : "a.circle.fill")
                    .font(.headline)
                    .foregroundStyle(provider.accent)
                Spacer()
                Button {
                    Task { await store.addAccount(provider) }
                } label: {
                    Label("Add account", systemImage: "plus")
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
                            refresh: { await store.refresh(account.id) },
                            reconnect: { await store.reconnect(account.id) }
                        )
                    }
                }

                if let error = store.providerErrors[provider] {
                    Label(error.message(locale: locale), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

private struct AccountSection: View {
    let state: ProviderPresentation
    let refresh: () async -> Void
    let reconnect: () async -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let snapshot = state.snapshot {
                UsageCard(
                    snapshot: snapshot,
                    accountName: accountName,
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
        state.account.identityLabel ?? String(
            localized: "account.number",
            defaultValue: "Account \(state.account.ordinal)",
            locale: locale
        )
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
                 ? String(localized: "Track your Codex usage and reset time.", locale: locale)
                 : String(localized: "Track your Claude Code usage and reset time.", locale: locale))
                .foregroundStyle(.secondary)
            Button {
                Task { await connect() }
            } label: {
                HStack {
                    if isConnecting { ProgressView().tint(.black) }
                    Text(isConnecting
                         ? String(localized: "Connecting…", locale: locale)
                         : String(localized: "Add account", locale: locale))
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
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.055))
        }
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
                 ? String(localized: "Connected, but no usage data has been received yet.", locale: locale)
                 : String(localized: "Session expired. Connect again.", locale: locale))
                .foregroundStyle(.secondary)
            Button {
                Task { await action() }
            } label: {
                HStack {
                    if isWorking { ProgressView().tint(.black) }
                    Text(isConnected
                         ? String(localized: "Retry refresh", locale: locale)
                         : String(localized: "Reconnect", locale: locale))
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
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct LoadingCard: View {
    let provider: AIProvider
    let accountName: String

    var body: some View {
        HStack(spacing: 14) {
            ProgressView().tint(provider.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(accountName).font(.headline)
                Text("Loading usage…").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
