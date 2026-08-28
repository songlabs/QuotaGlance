import Foundation
@testable import QuotaGlance
import QuotaGlanceCore
import XCTest

final class QuotaGlanceTests: XCTestCase {
    @MainActor
    func testRestoreOperationReturnsSuccessAfterSyncAndRefresh() async {
        var events: [String] = []

        let result = await performRestore(
            sync: { events.append("sync") },
            refreshEntitlements: { events.append("refresh") }
        )

        guard case .success = result else {
            return XCTFail("Expected restore success")
        }
        XCTAssertEqual(events, ["sync", "refresh"])
    }

    @MainActor
    func testRestoreOperationReturnsFailureWithoutRefreshing() async {
        struct RestoreError: Error {}
        var didRefresh = false

        let result = await performRestore(
            sync: { throw RestoreError() },
            refreshEntitlements: { didRefresh = true }
        )

        guard case .failure = result else {
            return XCTFail("Expected restore failure")
        }
        XCTAssertFalse(didRefresh)
    }

    func testRestoreFeedbackDistinguishesSuccessAndFailure() {
        XCTAssertEqual(
            restoreFeedbackLocalizationKey(succeeded: true),
            "Restore Completed"
        )
        XCTAssertEqual(
            restoreFeedbackLocalizationKey(succeeded: false),
            "Restore Failed"
        )
    }

    func testRemainingPercentageClampsBoundaries() {
        XCTAssertEqual(UsageWindow(usedPercentage: 0, resetAt: nil).remainingPercentage, 100)
        XCTAssertEqual(UsageWindow(usedPercentage: 28, resetAt: nil).remainingPercentage, 72)
        XCTAssertEqual(UsageWindow(usedPercentage: 100, resetAt: nil).remainingPercentage, 0)
        XCTAssertEqual(UsageWindow(usedPercentage: -1, resetAt: nil).remainingPercentage, 100)
        XCTAssertEqual(UsageWindow(usedPercentage: 101, resetAt: nil).remainingPercentage, 0)
    }

    func testNilWindowIsNotZeroRemaining() {
        let snapshot = UsageSnapshot(provider: .claude, session: nil, weekly: nil, updatedAt: Date())
        XCTAssertNil(snapshot.session)
        XCTAssertNil(snapshot.weekly)
    }

    func testSnapshotEnvelopeDefaultsToFreeAccess() {
        let envelope = SnapshotEnvelope(snapshots: [])

        XCTAssertEqual(envelope.accessLevel, .free)
        XCTAssertFalse(envelope.accessLevel.hasProFeatures)
    }

    func testLegacySnapshotEnvelopeWithoutAccessLevelFailsClosed() throws {
        let legacyJSON = #"{"version":1,"snapshots":[]}"#
        let envelope = try SnapshotCoding.decode(Data(legacyJSON.utf8))

        XCTAssertEqual(envelope.accessLevel, .free)
        XCTAssertFalse(envelope.accessLevel.hasProFeatures)
    }

    func testSettingsMembershipRouting() {
        XCTAssertTrue(SettingsUpgradeRouting.shouldPresentMembership(for: .free))
        XCTAssertTrue(SettingsUpgradeRouting.shouldPresentMembership(for: .trial))
        XCTAssertFalse(SettingsUpgradeRouting.shouldPresentMembership(for: .pro))
    }

    func testAutomaticRefreshOptionsAndEntitlements() {
        let expectedDurations: [TimeInterval?] = [
            nil,
            15 * 60,
            30 * 60,
            60 * 60,
            2 * 60 * 60,
            4 * 60 * 60,
        ]
        XCTAssertEqual(AutomaticRefreshInterval.allCases.map(\.timeInterval), expectedDurations)
        XCTAssertEqual(AutomaticRefreshInterval.defaultInterval, .fourHours)
        XCTAssertEqual(AutomaticRefreshInterval.fifteenMinutes.effective(for: .free), .fourHours)
        XCTAssertEqual(AutomaticRefreshInterval.fifteenMinutes.effective(for: .trial), .fifteenMinutes)
        XCTAssertEqual(AutomaticRefreshInterval.fifteenMinutes.effective(for: .pro), .fifteenMinutes)
        XCTAssertEqual(AutomaticRefreshInterval.disabled.effective(for: .free), .fourHours)
        XCTAssertEqual(AutomaticRefreshInterval.disabled.effective(for: .pro), .disabled)
    }

    func testLegacyAutomaticRefreshMigration() {
        let minuteCases: [(Int, AutomaticRefreshInterval)] = [
            (0, .disabled),
            (5, .fifteenMinutes),
            (15, .fifteenMinutes),
            (20, .thirtyMinutes),
            (45, .oneHour),
            (90, .twoHours),
            (120, .twoHours),
            (180, .fourHours),
            (300, .fourHours),
        ]
        for (value, expected) in minuteCases {
            XCTAssertEqual(
                AutomaticRefreshInterval.migratingLegacy(value: value, unit: "minute"),
                expected
            )
        }
    }

    func testOtherProOnlySelectionsPreserveStoredValues() {
        XCTAssertEqual(QuotaDisplayLimit.weekly.effective(for: .free), .fiveHour)
        XCTAssertEqual(QuotaDisplayLimit.weekly.effective(for: .trial), .weekly)
        XCTAssertEqual(QuotaDisplayLimit.weekly.effective(for: .pro), .weekly)

        let first = UUID()
        let second = UUID()
        let third = UUID()
        let stored = [second, third]
        XCTAssertEqual(
            WatchRefreshScope.accountIdentifiers(
                accounts: [first, second, third],
                selectedAccountIdentifiers: stored,
                hasProFeatures: false
            ),
            [first]
        )
        XCTAssertEqual(stored, [second, third])
        XCTAssertEqual(
            WatchRefreshScope.accountIdentifiers(
                accounts: [first, second, third],
                selectedAccountIdentifiers: stored,
                hasProFeatures: true
            ),
            [second, third]
        )
    }

    @MainActor
    func testDisplayAccountSelectionSwitchesBothProvidersInBothDirections() {
        let suiteName = "QuotaGlanceTests.DisplaySelectionStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = SelectionTestSnapshotCache()
        let purchaseManager = PurchaseManager(observesTransactions: false)
        purchaseManager.configureForScreenshot(
            accessLevel: .pro,
            trialEndsAt: nil,
            hasTrialTransaction: false,
            lifetimePrice: "$0.00"
        )
        let store = DashboardStore(
            providers: [:],
            credentials: KeychainCredentialStore(),
            registry: AccountRegistry(defaults: defaults),
            cache: cache,
            watchSync: SelectionTestWatchSync(),
            purchaseManager: purchaseManager,
            settingsDefaults: defaults,
            migrateLegacyCredentials: false
        )
        let accounts = [
            ProviderAccount(id: UUID(), provider: .codex, ordinal: 1, identityLabel: "Codex A"),
            ProviderAccount(id: UUID(), provider: .codex, ordinal: 2, identityLabel: "Codex B"),
            ProviderAccount(id: UUID(), provider: .claude, ordinal: 1, identityLabel: "Claude A"),
            ProviderAccount(id: UUID(), provider: .claude, ordinal: 2, identityLabel: "Claude B"),
        ]
        store.loadPreview(accounts.map {
            ProviderPresentation(
                account: $0,
                isConnected: true,
                snapshot: nil,
                isRefreshing: false,
                error: nil
            )
        })

        let codexAccounts = store.accounts.filter { $0.provider == .codex }
        let claudeAccounts = store.accounts.filter { $0.provider == .claude }
        XCTAssertEqual(codexAccounts.count, 2)
        XCTAssertEqual(claudeAccounts.count, 2)

        for (provider, accounts) in [(AIProvider.codex, codexAccounts), (.claude, claudeAccounts)] {
            store.selectAccount(accounts[1].id, for: provider)
            XCTAssertEqual(store.selectedAccountIdentifier(for: provider), accounts[1].id)
            XCTAssertEqual(store.selectedAccountIdentifiers[provider], accounts[1].id)
            XCTAssertEqual(cache.selectedAccountIdentifier(for: provider), accounts[1].id)

            store.selectAccount(accounts[0].id, for: provider)
            XCTAssertEqual(store.selectedAccountIdentifier(for: provider), accounts[0].id)
            XCTAssertEqual(store.selectedAccountIdentifiers[provider], accounts[0].id)
            XCTAssertEqual(cache.selectedAccountIdentifier(for: provider), accounts[0].id)
        }
    }

    @MainActor
    func testDisplayAccountSelectionPersistsForBothProviders() {
        let suiteName = "QuotaGlanceTests.DisplaySelection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let codexID = UUID()
        let claudeID = UUID()

        let cache = AppGroupSnapshotCache(defaults: defaults)
        cache.setSelectedAccountIdentifier(codexID, for: .codex)
        cache.setSelectedAccountIdentifier(claudeID, for: .claude)

        let restored = AppGroupSnapshotCache(defaults: UserDefaults(suiteName: suiteName))
        XCTAssertEqual(restored.selectedAccountIdentifier(for: .codex), codexID)
        XCTAssertEqual(restored.selectedAccountIdentifier(for: .claude), claudeID)
    }
}

@MainActor
private final class SelectionTestSnapshotCache: SnapshotCaching {
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
private final class SelectionTestWatchSync: PhoneWatchSynchronizing {
    func send(_ envelope: SnapshotEnvelope) {}
    func setRefreshHandler(_ handler: @escaping @MainActor () async -> Bool) {}
}
