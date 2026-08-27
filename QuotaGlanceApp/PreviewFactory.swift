import Foundation
import QuotaGlanceCore

@MainActor
enum PreviewFactory {
    static let codexAccount = ProviderAccount(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        provider: .codex,
        ordinal: 1,
        identityLabel: "Studio"
    )
    static let secondCodexAccount = ProviderAccount(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        provider: .codex,
        ordinal: 2,
        identityLabel: "Planning"
    )
    static let claudeAccount = ProviderAccount(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        provider: .claude,
        ordinal: 1,
        identityLabel: "Research"
    )

    static let codex = UsageSnapshot(
        provider: .codex,
        accountIdentifier: codexAccount.id,
        session: UsageWindow(usedPercentage: 28, resetAt: Date().addingTimeInterval(7_200)),
        weekly: UsageWindow(usedPercentage: 59, resetAt: Date().addingTimeInterval(345_600)),
        updatedAt: Date()
    )
    static let secondCodex = UsageSnapshot(
        provider: .codex,
        accountIdentifier: secondCodexAccount.id,
        session: UsageWindow(usedPercentage: 62, resetAt: Date().addingTimeInterval(8_200)),
        weekly: UsageWindow(usedPercentage: 21, resetAt: Date().addingTimeInterval(445_600)),
        updatedAt: Date().addingTimeInterval(-120)
    )
    static let claude = UsageSnapshot(
        provider: .claude,
        accountIdentifier: claudeAccount.id,
        session: UsageWindow(usedPercentage: 52, resetAt: Date().addingTimeInterval(9_000)),
        weekly: UsageWindow(usedPercentage: 37, resetAt: Date().addingTimeInterval(432_000)),
        updatedAt: Date()
    )

    static var normalStates: [ProviderPresentation] {
        [
            presentation(codexAccount, snapshot: codex),
            presentation(secondCodexAccount, snapshot: secondCodex),
            presentation(claudeAccount, snapshot: claude),
        ]
    }

    static var codexOnlyStates: [ProviderPresentation] {
        [presentation(codexAccount, snapshot: codex)]
    }

    static var claudeOnlyStates: [ProviderPresentation] {
        [presentation(claudeAccount, snapshot: claude)]
    }

    static var lowStates: [ProviderPresentation] {
        let low = UsageSnapshot(
            provider: .codex,
            accountIdentifier: codexAccount.id,
            session: UsageWindow(usedPercentage: 91, resetAt: Date().addingTimeInterval(600)),
            weekly: nil,
            updatedAt: Date()
        )
        return [presentation(codexAccount, snapshot: low)]
    }

    static var cachedStates: [ProviderPresentation] {
        let stale = UsageSnapshot(
            provider: .codex,
            accountIdentifier: codexAccount.id,
            session: codex.session,
            weekly: codex.weekly,
            updatedAt: Date().addingTimeInterval(-2_100)
        )
        return [presentation(codexAccount, snapshot: stale)]
    }

    static var errorStates: [ProviderPresentation] {
        [presentation(codexAccount, snapshot: codex, error: .network)]
    }

    static var loadingStates: [ProviderPresentation] {
        [ProviderPresentation(account: codexAccount, isConnected: true, snapshot: nil, isRefreshing: true, error: nil)]
    }

    static func dashboard(
        states: [ProviderPresentation],
        access: ScreenshotAccess? = nil
    ) -> DashboardStore {
        let providers: [AIProvider: any UsageProvider] = [
            .codex: PreviewProvider(provider: .codex),
            .claude: PreviewProvider(provider: .claude),
        ]
        let defaults = UserDefaults(suiteName: "QuotaGlancePreview.\(UUID().uuidString)")!
        let purchaseManager = PurchaseManager()
        let store = DashboardStore(
            providers: providers,
            credentials: KeychainCredentialStore(),
            registry: AccountRegistry(defaults: defaults),
            cache: PreviewCache(),
            watchSync: PreviewWatchSync(),
            purchaseManager: purchaseManager,
            settingsDefaults: defaults,
            migrateLegacyCredentials: false
        )
#if DEBUG
        if let access {
            purchaseManager.configureForScreenshot(
                accessLevel: access.accessLevel,
                trialEndsAt: access == .trial ? Date().addingTimeInterval(4 * 24 * 60 * 60) : nil,
                hasTrialTransaction: access == .trial || access == .trialExpired,
                lifetimePrice: "¥500"
            )
        }
#endif
        if !states.isEmpty {
            store.loadPreview(
                states,
                watchAccountIdentifiers: [codexAccount.id, claudeAccount.id]
            )
        }
        return store
    }

    private static func presentation(
        _ account: ProviderAccount,
        snapshot: UsageSnapshot,
        error: PresentationError? = nil
    ) -> ProviderPresentation {
        ProviderPresentation(
            account: account,
            isConnected: true,
            snapshot: snapshot,
            isRefreshing: false,
            error: error
        )
    }
}

@MainActor
private final class PreviewProvider: UsageProvider {
    let provider: AIProvider
    private var connected: Set<UUID> = []

    init(provider: AIProvider) { self.provider = provider }

    func isConnected(accountIdentifier: UUID) -> Bool {
        connected.contains(accountIdentifier)
    }

    func connect(accountIdentifier: UUID) async throws -> String? {
        connected.insert(accountIdentifier)
        return nil
    }

    func disconnect(accountIdentifier: UUID) async throws {
        connected.remove(accountIdentifier)
    }

    func refreshUsage(accountIdentifier: UUID) async throws -> UsageSnapshot {
        let snapshot = provider == .codex ? PreviewFactory.codex : PreviewFactory.claude
        return snapshot.assigned(to: accountIdentifier)
    }
}

@MainActor
private final class PreviewCache: SnapshotCaching {
    private var selections: [AIProvider: UUID] = [:]
    private var watchSelection: [UUID]?

    func load() -> SnapshotEnvelope? { nil }
    func save(_ envelope: SnapshotEnvelope) throws {}
    func remove(accountIdentifier: UUID) throws {}
    func selectedAccountIdentifier(for provider: AIProvider) -> UUID? { selections[provider] }
    func setSelectedAccountIdentifier(_ accountIdentifier: UUID?, for provider: AIProvider) {
        selections[provider] = accountIdentifier
    }
    func watchAccountIdentifiers() -> [UUID]? { watchSelection }
    func setWatchAccountIdentifiers(_ accountIdentifiers: [UUID]) {
        watchSelection = WatchAccountSelection.normalized(accountIdentifiers)
    }
}

@MainActor
private final class PreviewWatchSync: PhoneWatchSynchronizing {
    func send(_ envelope: SnapshotEnvelope) {}
    func setRefreshHandler(_ handler: @escaping @MainActor () async -> Bool) {}
}
