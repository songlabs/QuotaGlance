import Foundation
@testable import QuotaGlance
import QuotaGlanceCore
import XCTest

final class QuotaGlanceTests: XCTestCase {
    @MainActor
    private static var retainedRelaunchStores: [DashboardStore] = []

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

    func testCodexResetResponseDecodingAndPresentationPolicy() throws {
        func usageData(resetCreditField: String = "") -> Data {
            Data("""
            {
              "rate_limit": {
                "primary_window": {
                  "used_percent": 25,
                  "limit_window_seconds": 18000,
                  "reset_at": 1000
                },
                "secondary_window": {
                  "used_percent": 50,
                  "limit_window_seconds": 604800,
                  "reset_at": 2000
                }
              }
              \(resetCreditField)
            }
            """.utf8)
        }

        let two = try UsageResponseDecoder.decodeCodex(usageData(
            resetCreditField: #", "rate_limit_reset_credits":{"available_count":2}"#
        ))
        let zero = try UsageResponseDecoder.decodeCodex(usageData(
            resetCreditField: #", "rate_limit_reset_credits":{"available_count":0}"#
        ))
        let missing = try UsageResponseDecoder.decodeCodex(usageData())
        let malformed = try UsageResponseDecoder.decodeCodex(usageData(
            resetCreditField: #", "rate_limit_reset_credits":{"available_count":"unexpected"}"#
        ))

        XCTAssertEqual(two.availableResetCount, 2)
        XCTAssertEqual(zero.availableResetCount, 0)
        XCTAssertNil(missing.availableResetCount)
        XCTAssertNil(malformed.availableResetCount)
        XCTAssertEqual(two.session?.resetAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(two.weekly?.resetAt, Date(timeIntervalSince1970: 2_000))
        XCTAssertTrue(ResetCreditPresentationPolicy.allowsExpansion(
            provider: .codex,
            availableCount: two.availableResetCount
        ))
        XCTAssertFalse(ResetCreditPresentationPolicy.allowsExpansion(
            provider: .codex,
            availableCount: zero.availableResetCount
        ))
        XCTAssertFalse(ResetCreditPresentationPolicy.showsRow(
            provider: .codex,
            availableCount: nil
        ))
        XCTAssertTrue(ResetCreditPresentationPolicy.showsRow(
            provider: .codex,
            availableCount: zero.availableResetCount
        ))
        XCTAssertFalse(ResetCreditPresentationPolicy.showsRow(
            provider: .claude,
            availableCount: 2
        ))

        let details = try UsageResponseDecoder.decodeCodexResetCredits(Data(#"""
        {
          "credits": [
            {
              "id": "later",
              "reset_type": "codex_rate_limits",
              "status": "available",
              "expires_at": "2026-10-04T09:39:00Z",
              "title": "Full reset"
            },
            {
              "id": "no-expiration",
              "reset_type": "codex_rate_limits",
              "status": "available",
              "expires_at": null
            },
            {
              "id": "earlier",
              "reset_type": "codex_rate_limits",
              "status": "available",
              "expires_at": "2026-09-21T06:31:00Z",
              "title": "Sooner reset"
            },
            {
              "id": "redeemed",
              "reset_type": "codex_rate_limits",
              "status": "redeemed",
              "expires_at": "2026-09-10T00:00:00Z",
              "title": "Already used"
            }
          ],
          "available_count": 99
        }
        """#.utf8))
        let sorted = ResetCreditPresentationPolicy.sortedAvailableCredits(in: details)

        XCTAssertEqual(sorted.map(\.id), ["earlier", "later", "no-expiration"])
        XCTAssertEqual(details.credits[0].title, "Full reset")
        XCTAssertNil(details.credits[1].expiresAt)
        XCTAssertEqual(two.availableResetCount, 2)
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

    func testLegacySnapshotEnvelopeDecodesWithoutResetCount() throws {
        let legacyJSON = #"{"version":1,"snapshots":[{"provider":"codex","session":null,"weekly":null,"updatedAt":0}]}"#
        let envelope = try SnapshotCoding.decode(Data(legacyJSON.utf8))

        XCTAssertNil(envelope.snapshots.first?.availableResetCount)
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
    func testResetDetailsLoadOnceAndFailureDoesNotReplaceUsageSnapshot() async throws {
        let registrySuite = "QuotaGlanceTests.ResetDetails.Registry.\(UUID().uuidString)"
        let cacheSuite = "QuotaGlanceTests.ResetDetails.Cache.\(UUID().uuidString)"
        let settingsSuite = "QuotaGlanceTests.ResetDetails.Settings.\(UUID().uuidString)"
        let registryDefaults = UserDefaults(suiteName: registrySuite)!
        let cacheDefaults = UserDefaults(suiteName: cacheSuite)!
        let settingsDefaults = UserDefaults(suiteName: settingsSuite)!
        defer {
            registryDefaults.removePersistentDomain(forName: registrySuite)
            cacheDefaults.removePersistentDomain(forName: cacheSuite)
            settingsDefaults.removePersistentDomain(forName: settingsSuite)
        }

        let account = ProviderAccount(id: UUID(), provider: .codex, ordinal: 1)
        let snapshot = UsageSnapshot(
            provider: .codex,
            accountIdentifier: account.id,
            session: UsageWindow(usedPercentage: 25, resetAt: nil),
            weekly: UsageWindow(usedPercentage: 50, resetAt: nil),
            availableResetCount: 2,
            updatedAt: Date()
        )
        let details = CodexResetCreditDetails(credits: [
            CodexResetCredit(
                id: "one-detail",
                status: "available",
                title: "Provider reset",
                expiresAt: Date().addingTimeInterval(3_600)
            ),
        ])
        let provider = ResetDetailsUsageProvider(details: details)
        let store = DashboardStore(
            providers: [.codex: provider],
            credentials: KeychainCredentialStore(),
            registry: AccountRegistry(defaults: registryDefaults),
            cache: AppGroupSnapshotCache(defaults: cacheDefaults),
            watchSync: DemoIsolationWatchSync(),
            purchaseManager: PurchaseManager(observesTransactions: false),
            settingsDefaults: settingsDefaults,
            migrateLegacyCredentials: false
        )
        store.loadPreview([ProviderPresentation(
            account: account,
            isConnected: true,
            snapshot: snapshot,
            isRefreshing: false,
            error: nil
        )])

        await store.loadResetCreditDetails(account.id)
        await store.loadResetCreditDetails(account.id)
        XCTAssertEqual(provider.detailsRequestCount, 1)
        XCTAssertEqual(store.states[account.id]?.resetCreditDetails, details)
        XCTAssertEqual(store.states[account.id]?.snapshot?.availableResetCount, 2)

        store.states[account.id]?.resetCreditDetails = nil
        provider.nextError = .network
        await store.loadResetCreditDetails(account.id)

        XCTAssertEqual(provider.detailsRequestCount, 2)
        XCTAssertEqual(store.states[account.id]?.snapshot, snapshot)
        XCTAssertNil(store.states[account.id]?.error)
        XCTAssertEqual(store.states[account.id]?.resetCreditDetailsError, .network)
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
            displayLimit: .fiveHour,
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
        XCTAssertEqual(
            store.states[PreviewFactory.codexAccount.id]?.snapshot?.availableResetCount,
            2
        )
        XCTAssertEqual(
            store.states[PreviewFactory.codexAccount.id]?.resetCreditDetails?.credits.count,
            2
        )
        XCTAssertNil(store.states[PreviewFactory.claudeAccount.id]?.snapshot?.availableResetCount)
        XCTAssertNil(store.states[PreviewFactory.claudeAccount.id]?.resetCreditDetails)
        XCTAssertEqual(registry.load(), [productionAccount])
        XCTAssertEqual(store.appLanguage, .japanese)

        await store.addAccount(.codex)
        let appRefreshSucceeded = await store.refreshAll(force: true)
        let watchRefreshSucceeded = await watchSync.requestRefresh()
        XCTAssertTrue(appRefreshSucceeded)
        XCTAssertTrue(watchRefreshSucceeded)
        XCTAssertTrue(store.isShowingAppReviewDemo)
        XCTAssertEqual(provider.connectCount, 0)
        XCTAssertEqual(provider.refreshCount, 0)
        XCTAssertEqual(provider.disconnectCount, 0)
        XCTAssertEqual(registry.load(), [productionAccount])

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

        // Cover the opposite startup order: Demo can be enabled after
        // entitlements load but before DashboardView records the active scene.
        store.stopForegroundAutomaticRefresh()
        XCTAssertFalse(store.isForegroundAutomaticRefreshActive)
        store.enableAppReviewDemo()
        XCTAssertFalse(store.isForegroundAutomaticRefreshActive)
        store.startForegroundAutomaticRefresh()
        XCTAssertTrue(store.isForegroundAutomaticRefreshActive)
        let externallyUpdatedTrialEnd = Date().addingTimeInterval(3_600)
        purchaseManager.configureForScreenshot(
            accessLevel: .trial,
            trialEndsAt: externallyUpdatedTrialEnd,
            hasTrialTransaction: true,
            lifetimePrice: "Test"
        )
        XCTAssertEqual(store.accessLevel, .pro)
        store.disableAppReviewDemo()
        XCTAssertTrue(store.isForegroundAutomaticRefreshActive)
        XCTAssertEqual(store.accessLevel, .trial)
        let externallyUpdatedEnvelope = try XCTUnwrap(cache.load())
        XCTAssertFalse(externallyUpdatedEnvelope.isAppReviewDemo)
        XCTAssertEqual(externallyUpdatedEnvelope.accessLevel, .trial)
        XCTAssertEqual(externallyUpdatedEnvelope.proAccessExpiresAt, externallyUpdatedTrialEnd)
        XCTAssertEqual(watchSync.sentEnvelopes.last, externallyUpdatedEnvelope)
        XCTAssertNotEqual(
            TrialEntitlementTaskIdentity(
                accessLevel: .trial,
                isAppReviewDemoEnabled: true
            ),
            TrialEntitlementTaskIdentity(
                accessLevel: .trial,
                isAppReviewDemoEnabled: false
            )
        )
        store.stopForegroundAutomaticRefresh()
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

        // A force-quit discards both process heaps without running app object
        // deinitializers. Retaining these stores gives the in-process test the
        // same lifetime boundary while it verifies the persisted recovery path.
        Self.retainedRelaunchStores.append(contentsOf: [firstStore, secondStore])
    }
}

@MainActor
private final class ResetDetailsUsageProvider: UsageProvider, CodexResetCreditDetailsProvider {
    let provider = AIProvider.codex
    let details: CodexResetCreditDetails
    var nextError: UsageProviderError?
    private(set) var detailsRequestCount = 0

    init(details: CodexResetCreditDetails) {
        self.details = details
    }

    func isConnected(accountIdentifier: UUID) -> Bool { true }
    func connect(accountIdentifier: UUID) async throws -> String? { nil }
    func disconnect(accountIdentifier: UUID) async throws {}

    func refreshUsage(accountIdentifier: UUID) async throws -> UsageSnapshot {
        UsageSnapshot(provider: .codex, session: nil, weekly: nil, updatedAt: Date())
    }

    func resetCreditDetails(accountIdentifier: UUID) async throws -> CodexResetCreditDetails {
        detailsRequestCount += 1
        if let nextError { throw nextError }
        return details
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
