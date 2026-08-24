import Foundation
import QuotaGlanceCore

@MainActor
enum PreviewFactory {
    static let codex = UsageSnapshot(
        provider: .codex,
        session: UsageWindow(usedPercentage: 28, resetAt: Date().addingTimeInterval(7_200)),
        weekly: UsageWindow(usedPercentage: 59, resetAt: Date().addingTimeInterval(345_600)),
        updatedAt: Date()
    )
    static let claude = UsageSnapshot(
        provider: .claude,
        session: UsageWindow(usedPercentage: 52, resetAt: Date().addingTimeInterval(9_000)),
        weekly: UsageWindow(usedPercentage: 37, resetAt: Date().addingTimeInterval(432_000)),
        updatedAt: Date()
    )

    static var normalStates: [ProviderPresentation] {
        [
            ProviderPresentation(provider: .codex, isConnected: true, snapshot: codex, isRefreshing: false, errorMessage: nil),
            ProviderPresentation(provider: .claude, isConnected: true, snapshot: claude, isRefreshing: false, errorMessage: nil),
        ]
    }

    static var codexOnlyStates: [ProviderPresentation] {
        [ProviderPresentation(provider: .codex, isConnected: true, snapshot: codex, isRefreshing: false, errorMessage: nil)]
    }

    static var claudeOnlyStates: [ProviderPresentation] {
        [ProviderPresentation(provider: .claude, isConnected: true, snapshot: claude, isRefreshing: false, errorMessage: nil)]
    }

    static var lowStates: [ProviderPresentation] {
        let low = UsageSnapshot(
            provider: .codex,
            session: UsageWindow(usedPercentage: 91, resetAt: Date().addingTimeInterval(600)),
            weekly: nil,
            updatedAt: Date()
        )
        return [ProviderPresentation(provider: .codex, isConnected: true, snapshot: low, isRefreshing: false, errorMessage: nil)]
    }

    static var cachedStates: [ProviderPresentation] {
        let stale = UsageSnapshot(
            provider: .codex,
            session: codex.session,
            weekly: codex.weekly,
            updatedAt: Date().addingTimeInterval(-2_100)
        )
        return [ProviderPresentation(provider: .codex, isConnected: true, snapshot: stale, isRefreshing: false, errorMessage: nil)]
    }

    static var errorStates: [ProviderPresentation] {
        [ProviderPresentation(
            provider: .codex,
            isConnected: true,
            snapshot: codex,
            isRefreshing: false,
            errorMessage: String(localized: "Unable to refresh. Check your connection.")
        )]
    }

    static var loadingStates: [ProviderPresentation] {
        [ProviderPresentation(provider: .codex, isConnected: true, snapshot: nil, isRefreshing: true, errorMessage: nil)]
    }

    static func dashboard(states: [ProviderPresentation]) -> DashboardStore {
        let providers: [AIProvider: any UsageProvider] = [
            .codex: PreviewProvider(provider: .codex),
            .claude: PreviewProvider(provider: .claude),
        ]
        let store = DashboardStore(providers: providers, cache: PreviewCache(), watchSync: PreviewWatchSync())
        if !states.isEmpty { store.loadPreview(states) }
        return store
    }
}

@MainActor
private final class PreviewProvider: UsageProvider {
    let provider: AIProvider
    var isConnected = false
    init(provider: AIProvider) { self.provider = provider }
    func connect() async throws { isConnected = true }
    func disconnect() async throws { isConnected = false }
    func refreshUsage() async throws -> UsageSnapshot {
        provider == .codex ? PreviewFactory.codex : PreviewFactory.claude
    }
}

@MainActor
private final class PreviewCache: SnapshotCaching {
    func load() -> SnapshotEnvelope? { nil }
    func save(_ envelope: SnapshotEnvelope) throws {}
    func remove(_ provider: AIProvider) throws {}
}

@MainActor
private final class PreviewWatchSync: PhoneWatchSynchronizing {
    func send(_ envelope: SnapshotEnvelope) {}
}
