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
                    LazyVStack(spacing: 14) {
                        ForEach(AIProvider.allCases) { provider in
                            ProviderSection(
                                state: store.states[provider] ?? ProviderPresentation(
                                    provider: provider,
                                    isConnected: false,
                                    snapshot: nil,
                                    isRefreshing: false,
                                    errorMessage: nil
                                ),
                                connect: { await store.connect(provider) },
                                refresh: { await store.refresh(provider) }
                            )
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

private struct ProviderSection: View {
    let state: ProviderPresentation
    let connect: () async -> Void
    let refresh: () async -> Void

    var body: some View {
        Group {
            if let snapshot = state.snapshot {
                UsageCard(
                    snapshot: snapshot,
                    isRefreshing: state.isRefreshing,
                    errorMessage: state.errorMessage,
                    reconnect: state.isConnected ? nil : connect
                )
            } else if state.isConnected, state.isRefreshing {
                LoadingCard(provider: state.provider)
            } else {
                ConnectCard(
                    provider: state.provider,
                    isConnected: state.isConnected,
                    isConnecting: state.isRefreshing,
                    errorMessage: state.errorMessage,
                    action: state.isConnected ? refresh : connect
                )
            }
        }
    }
}

private struct ConnectCard: View {
    let provider: AIProvider
    let isConnected: Bool
    let isConnecting: Bool
    let errorMessage: String?
    let action: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(provider.displayName, systemImage: provider == .codex ? "sparkles" : "a.circle.fill")
                .font(.headline)
                .foregroundStyle(provider.accent)
            Text(description)
                .foregroundStyle(.secondary)
            Button {
                Task { await action() }
            } label: {
                HStack {
                    if isConnecting { ProgressView().tint(.black) }
                    Text(actionTitle)
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

    private var description: String {
        if isConnected {
            return String(localized: "Connected, but no usage data has been received yet.")
        }
        return provider == .codex
            ? String(localized: "Track your Codex usage and reset time.")
            : String(localized: "Track your Claude Code usage and reset time.")
    }

    private var actionTitle: String {
        if isConnecting {
            return isConnected ? String(localized: "Refreshing…") : String(localized: "Connecting…")
        }
        if isConnected {
            return String(localized: "Retry refresh")
        }
        return String(localized: "connect.provider", defaultValue: "Connect \(provider.displayName)")
    }
}

private struct LoadingCard: View {
    let provider: AIProvider

    var body: some View {
        HStack(spacing: 14) {
            ProgressView().tint(provider.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(provider.displayName).font(.headline)
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

#Preview("Codex only") {
    DashboardView(store: PreviewFactory.dashboard(states: PreviewFactory.codexOnlyStates))
}

#Preview("Claude only") {
    DashboardView(store: PreviewFactory.dashboard(states: PreviewFactory.claudeOnlyStates))
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
