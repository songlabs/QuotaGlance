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

    func testAppReviewDemoUnlockRequiresSevenVersionTaps() {
        var count = 0
        for _ in 0..<6 {
            count = AppReviewDemoUnlock.nextTapCount(after: count)
            XCTAssertFalse(AppReviewDemoUnlock.shouldUnlock(afterTapCount: count))
        }
        count = AppReviewDemoUnlock.nextTapCount(after: count)
        XCTAssertTrue(AppReviewDemoUnlock.shouldUnlock(afterTapCount: count))
        XCTAssertEqual(count, 7)
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

    @MainActor
    func testAppReviewDemoIsolatesEntitlementAccountsRefreshAndSharedPayloads() async throws {
        let registrySuite = "QuotaGlanceTests.Demo.Registry.\(UUID().uuidString)"
        let cacheSuite = "QuotaGlanceTests.Demo.Cache.\(UUID().uuidString)"
        let settingsSuite = "QuotaGlanceTests.Demo.Settings.\(UUID().uuidString)"
        let registryDefaults = UserDefaults(suiteName: registrySuite)!
        let cacheDefaults = UserDefaults(suiteName: cacheSuite)!
        let settingsDefaults = UserDefaults(suiteName: settingsSuite)!
        defer {
            registryDefaults.removePersistentDomain(forName: registrySuite)
            cacheDefaults.removePersistentDomain(forName: cacheSuite)
            settingsDefaults.removePersistentDomain(forName: settingsSuite)
        }

        let productionAccount = ProviderAccount(
            id: UUID(),
            provider: .codex,
            ordinal: 1,
            identityLabel: "Production"
        )
        let productionSnapshot = UsageSnapshot(
            provider: .codex,
            accountIdentifier: productionAccount.id,
            session: UsageWindow(usedPercentage: 10, resetAt: nil),
            weekly: UsageWindow(usedPercentage: 20, resetAt: nil),
            updatedAt: Date()
        )
        let productionEnvelope = SnapshotEnvelope(
            snapshots: [productionSnapshot],
            displayLimit: .weekly,
            accounts: [AccountDisplayMetadata(
                id: productionAccount.id,
                provider: .codex,
                ordinal: 1,
                displayName: "Production"
            )],
            watchAccountIdentifiers: [productionAccount.id],
            accessLevel: .free
        )

        let registry = AccountRegistry(defaults: registryDefaults)
        var productionAccounts: [ProviderAccount] = []
        registry.add(productionAccount, to: &productionAccounts)
        let cache = AppGroupSnapshotCache(defaults: cacheDefaults)
        try cache.save(productionEnvelope)
        cache.defaultProvider = .claude
        cache.displayLimit = .weekly
        cache.setSelectedAccountIdentifier(productionAccount.id, for: .codex)
        cache.setWatchAccountIdentifiers([productionAccount.id])
        AutomaticRefreshPreferences.save(.fifteenMinutes, to: settingsDefaults)
        settingsDefaults.set(AppLanguage.japanese.rawValue, forKey: AppLanguage.defaultsKey)

        let provider = DemoIsolationUsageProvider(provider: .codex)
        let watchSync = DemoIsolationWatchSync()
        let purchaseManager = PurchaseManager(observesTransactions: false)
        purchaseManager.configureForScreenshot(
            accessLevel: .free,
            trialEndsAt: nil,
            hasTrialTransaction: false,
            lifetimePrice: "Test"
        )
        let store = DashboardStore(
            providers: [.codex: provider],
            credentials: KeychainCredentialStore(),
            registry: registry,
            cache: cache,
            watchSync: watchSync,
            purchaseManager: purchaseManager,
            settingsDefaults: settingsDefaults,
            migrateLegacyCredentials: false
        )

        store.startForegroundAutomaticRefresh()
        XCTAssertTrue(store.isForegroundAutomaticRefreshActive)
        store.enableAppReviewDemo()

        XCTAssertTrue(store.isAppReviewDemoEnabled)
        XCTAssertFalse(store.isForegroundAutomaticRefreshActive)
        XCTAssertEqual(store.accessLevel, .pro)
        XCTAssertEqual(purchaseManager.accessLevel, .free)
        XCTAssertEqual(store.accounts.count, 3)
        XCTAssertEqual(store.accounts.filter { $0.provider == .codex }.count, 2)
        XCTAssertEqual(store.accounts.filter { $0.provider == .claude }.count, 1)
        XCTAssertTrue(store.accounts.allSatisfy { !($0.identityLabel ?? "").contains("@") })
        XCTAssertEqual(registry.load(), [productionAccount])
        XCTAssertEqual(store.appLanguage, .japanese)

        let appRefreshSucceeded = await store.refreshAll(force: true)
        let watchRefreshSucceeded = await watchSync.requestRefresh()
        XCTAssertTrue(appRefreshSucceeded)
        XCTAssertTrue(watchRefreshSucceeded)
        XCTAssertEqual(provider.connectCount, 0)
        XCTAssertEqual(provider.refreshCount, 0)
        XCTAssertEqual(provider.disconnectCount, 0)

        store.setAppReviewDemoAccessLevel(.free)
        let freeEnvelope = try XCTUnwrap(cache.load())
        XCTAssertTrue(freeEnvelope.isAppReviewDemo)
        XCTAssertEqual(freeEnvelope.accessLevel, .free)
        XCTAssertEqual(freeEnvelope.accounts.count, 1)
        XCTAssertEqual(freeEnvelope.snapshots.count, 1)
        XCTAssertEqual(freeEnvelope.watchAccountPresentations.count, 1)
        XCTAssertEqual(freeEnvelope.effectiveDisplayLimit(), .fiveHour)
        XCTAssertEqual(store.effectiveRefreshInterval, .fourHours)

        store.setAppReviewDemoAccessLevel(.trial)
        store.updateRefreshInterval(.twoHours)
        store.updateDisplayLimit(.weekly)
        let trialEnvelope = try XCTUnwrap(cache.load())
        XCTAssertTrue(trialEnvelope.hasProFeatures())
        XCTAssertEqual(trialEnvelope.accounts.count, 3)
        XCTAssertEqual(trialEnvelope.watchAccountPresentations.count, 2)
        XCTAssertEqual(trialEnvelope.effectiveDisplayLimit(), .weekly)
        XCTAssertEqual(store.effectiveRefreshInterval, .twoHours)

        store.setAppReviewDemoAccessLevel(.pro)
        store.defaultProvider = .claude
        store.selectAccount(PreviewFactory.secondCodexAccount.id, for: .codex)
        let proEnvelope = try XCTUnwrap(cache.load())
        XCTAssertEqual(proEnvelope.accessLevel, .pro)
        XCTAssertEqual(purchaseManager.accessLevel, .free)
        XCTAssertEqual(proEnvelope.appReviewDemoDefaultProvider, .claude)
        XCTAssertEqual(
            AppReviewDemoWidgetPolicy.selectedAccountIdentifier(for: .codex, in: proEnvelope),
            PreviewFactory.secondCodexAccount.id
        )
        XCTAssertEqual(
            AppReviewDemoWidgetPolicy.selectedAccountIdentifier(for: .claude, in: proEnvelope),
            PreviewFactory.claudeAccount.id
        )
        let payloadText = String(decoding: try SnapshotCoding.encode(proEnvelope), as: UTF8.self)
        XCTAssertFalse(payloadText.localizedCaseInsensitiveContains("Bearer"))
        XCTAssertFalse(payloadText.localizedCaseInsensitiveContains("password"))
        XCTAssertFalse(payloadText.localizedCaseInsensitiveContains("secret"))
        XCTAssertFalse(payloadText.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(payloadText.contains("@"))

        store.appLanguage = .english
        XCTAssertEqual(
            settingsDefaults.string(forKey: AppLanguage.defaultsKey),
            AppLanguage.japanese.rawValue
        )
        store.disableAppReviewDemo()

        XCTAssertFalse(store.isAppReviewDemoEnabled)
        XCTAssertTrue(store.isForegroundAutomaticRefreshActive)
        XCTAssertEqual(store.accessLevel, .free)
        XCTAssertEqual(store.accounts, [productionAccount])
        XCTAssertEqual(registry.load(), [productionAccount])
        XCTAssertEqual(cache.load(), productionEnvelope)
        XCTAssertEqual(cache.defaultProvider, .claude)
        XCTAssertEqual(cache.displayLimit, .weekly)
        XCTAssertEqual(cache.selectedAccountIdentifier(for: .codex), productionAccount.id)
        XCTAssertEqual(cache.watchAccountIdentifiers(), [productionAccount.id])
        XCTAssertEqual(store.refreshInterval, .fifteenMinutes)
        XCTAssertEqual(store.appLanguage, .japanese)
        XCTAssertEqual(
            settingsDefaults.string(forKey: AppLanguage.defaultsKey),
            AppLanguage.japanese.rawValue
        )
        XCTAssertEqual(watchSync.sentEnvelopes.last, productionEnvelope)
    }

    @MainActor
    func testAppReviewDemoRelaunchRestoresProductionSharedSnapshot() throws {
        let registrySuite = "QuotaGlanceTests.DemoRelaunch.Registry.\(UUID().uuidString)"
        let cacheSuite = "QuotaGlanceTests.DemoRelaunch.Cache.\(UUID().uuidString)"
        let settingsSuite = "QuotaGlanceTests.DemoRelaunch.Settings.\(UUID().uuidString)"
        let registryDefaults = UserDefaults(suiteName: registrySuite)!
        let cacheDefaults = UserDefaults(suiteName: cacheSuite)!
        let settingsDefaults = UserDefaults(suiteName: settingsSuite)!
        defer {
            registryDefaults.removePersistentDomain(forName: registrySuite)
            cacheDefaults.removePersistentDomain(forName: cacheSuite)
            settingsDefaults.removePersistentDomain(forName: settingsSuite)
        }

        let productionAccount = ProviderAccount(id: UUID(), provider: .codex, ordinal: 1)
        let productionEnvelope = SnapshotEnvelope(
            snapshots: [UsageSnapshot(
                provider: .codex,
                accountIdentifier: productionAccount.id,
                session: UsageWindow(usedPercentage: 12, resetAt: nil),
                weekly: UsageWindow(usedPercentage: 34, resetAt: nil),
                updatedAt: Date()
            )],
            accounts: [AccountDisplayMetadata(
                id: productionAccount.id,
                provider: .codex,
                ordinal: 1,
                displayName: "Account 1"
            )],
            watchAccountIdentifiers: [productionAccount.id],
            accessLevel: .free
        )
        let registry = AccountRegistry(defaults: registryDefaults)
        var accounts: [ProviderAccount] = []
        registry.add(productionAccount, to: &accounts)
        let cache = AppGroupSnapshotCache(defaults: cacheDefaults)
        try cache.save(productionEnvelope)

        let firstWatchSync = DemoIsolationWatchSync()
        let firstPurchaseManager = PurchaseManager(observesTransactions: false)
        firstPurchaseManager.configureForScreenshot(
            accessLevel: .free,
            trialEndsAt: nil,
            hasTrialTransaction: false,
            lifetimePrice: "Test"
        )
        let firstStore = DashboardStore(
            providers: [:],
            credentials: KeychainCredentialStore(),
            registry: registry,
            cache: cache,
            watchSync: firstWatchSync,
            purchaseManager: firstPurchaseManager,
            settingsDefaults: settingsDefaults,
            migrateLegacyCredentials: false
        )
        firstStore.enableAppReviewDemo()
        XCTAssertTrue(try XCTUnwrap(cache.load()).isAppReviewDemo)

        // A new store simulates a force-quit/relaunch without a graceful Demo exit.
        let secondWatchSync = DemoIsolationWatchSync()
        let secondStore = DashboardStore(
            providers: [:],
            credentials: KeychainCredentialStore(),
            registry: registry,
            cache: AppGroupSnapshotCache(defaults: UserDefaults(suiteName: cacheSuite)),
            watchSync: secondWatchSync,
            purchaseManager: PurchaseManager(observesTransactions: false),
            settingsDefaults: UserDefaults(suiteName: settingsSuite)!,
            migrateLegacyCredentials: false
        )

        XCTAssertFalse(secondStore.isAppReviewDemoEnabled)
        XCTAssertEqual(secondStore.accounts, [productionAccount])
        XCTAssertEqual(secondStore.states[productionAccount.id]?.snapshot, productionEnvelope.snapshots.first)
        XCTAssertEqual(cache.load(), productionEnvelope)
        XCTAssertEqual(secondWatchSync.sentEnvelopes, [productionEnvelope])
        XCTAssertNil(cacheDefaults.object(forKey: AppGroupSnapshotCache.appReviewDemoBackupActiveKey))
        XCTAssertNil(cacheDefaults.data(forKey: AppGroupSnapshotCache.appReviewDemoProductionSnapshotKey))
    }
}

@MainActor
private final class DemoIsolationUsageProvider: UsageProvider {
    let provider: AIProvider
    private(set) var connectCount = 0
    private(set) var refreshCount = 0
    private(set) var disconnectCount = 0

    init(provider: AIProvider) {
        self.provider = provider
    }

    func isConnected(accountIdentifier: UUID) -> Bool { true }

    func connect(accountIdentifier: UUID) async throws -> String? {
        connectCount += 1
        return nil
    }

    func disconnect(accountIdentifier: UUID) async throws {
        disconnectCount += 1
    }

    func refreshUsage(accountIdentifier: UUID) async throws -> UsageSnapshot {
        refreshCount += 1
        return UsageSnapshot(
            provider: provider,
            session: nil,
            weekly: nil,
            updatedAt: Date()
        )
    }
}

@MainActor
private final class DemoIsolationWatchSync: PhoneWatchSynchronizing {
    private(set) var sentEnvelopes: [SnapshotEnvelope] = []
    private var refreshHandler: (@MainActor () async -> Bool)?

    func send(_ envelope: SnapshotEnvelope) {
        sentEnvelopes.append(envelope)
    }

    func setRefreshHandler(_ handler: @escaping @MainActor () async -> Bool) {
        refreshHandler = handler
    }

    func requestRefresh() async -> Bool {
        await refreshHandler?() ?? false
    }
}
