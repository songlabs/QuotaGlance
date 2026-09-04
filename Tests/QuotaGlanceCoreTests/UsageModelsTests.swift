import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Remaining percentage")
struct UsageModelsTests {
    @Test("Snapshots cannot publish before StoreKit entitlement initialization")
    func entitlementPublicationInitialization() {
        #expect(!EntitlementPublicationPolicy.canPublish(isEntitlementLoaded: false))
        #expect(EntitlementPublicationPolicy.canPublish(isEntitlementLoaded: true))
    }

    @Test("Snapshot Trial expiry is evaluated independently by every client")
    func snapshotTrialExpiry() {
        let expiry = Date(timeIntervalSince1970: 10_000)
        let envelope = SnapshotEnvelope(
            snapshots: [],
            accessLevel: .trial,
            proAccessExpiresAt: expiry
        )

        #expect(envelope.hasProFeatures(at: expiry.addingTimeInterval(-1)))
        #expect(!envelope.hasProFeatures(at: expiry))
        #expect(!envelope.hasProFeatures(at: expiry.addingTimeInterval(1)))
        #expect(envelope.effectiveDisplayLimit(at: expiry) == .fiveHour)
    }

    @Test("Trial timelines include an expiry entry")
    func trialTimelineEntries() {
        let now = Date(timeIntervalSince1970: 9_000)
        let expiry = Date(timeIntervalSince1970: 10_000)
        let trial = SnapshotEnvelope(
            snapshots: [],
            accessLevel: .trial,
            proAccessExpiresAt: expiry
        )

        #expect(trial.timelineEntryDates(from: now) == [now, expiry])
        #expect(trial.timelineEntryDates(from: expiry) == [expiry])
        #expect(SnapshotEnvelope(snapshots: [], accessLevel: .pro).timelineEntryDates(from: now) == [now])
    }

    @Test("Settings membership routes Free and Trial, but not Pro, to Upgrade")
    func settingsMembershipRouting() {
        #expect(SettingsUpgradeRouting.shouldPresentMembership(for: .free))
        #expect(SettingsUpgradeRouting.shouldPresentMembership(for: .trial))
        #expect(!SettingsUpgradeRouting.shouldPresentMembership(for: .pro))
    }

    @Test("StoreKit purchase dates resolve Free, Trial, and Pro states")
    func accessResolution() {
        let day: TimeInterval = 24 * 60 * 60
        let duration = 7 * day
        let now = Date(timeIntervalSince1970: 20 * day)
        let resolve: (Bool, Date?, Date) -> AccessLevel = { hasLifetime, trialDate, effectiveNow in
            .resolve(
                hasLifetimePurchase: hasLifetime,
                trialPurchaseDate: trialDate,
                trialDuration: duration,
                now: effectiveNow
            )
        }

        // New user: no transaction, so Free and eligible to obtain the Trial product.
        #expect(resolve(false, nil, now) == .free)
        #expect(resolve(false, now, now) == .trial)
        #expect(resolve(false, now.addingTimeInterval(-6 * day), now) == .trial)
        #expect(resolve(false, now.addingTimeInterval(-8 * day), now) == .free)
        #expect(resolve(true, now.addingTimeInterval(-8 * day), now) == .pro)
        #expect(resolve(true, now, now) == .pro)

        // Restore uses the original purchase date and cannot restart an expired trial.
        let originalExpiredPurchase = now.addingTimeInterval(-30 * day)
        #expect(resolve(false, originalExpiredPurchase, now) == .free)
        #expect(resolve(true, nil, now) == .pro)

        // A greatest-observed clock value prevents moving time backwards from extending Trial.
        let trialPurchase = now.addingTimeInterval(-6 * day)
        let lastSeen = trialPurchase.addingTimeInterval(8 * day)
        let rolledBackClock = trialPurchase.addingTimeInterval(day)
        #expect(resolve(false, trialPurchase, max(lastSeen, rolledBackClock)) == .free)
    }

    @Test("Used percentage converts to remaining", arguments: [
        (0.0, 100.0),
        (28.0, 72.0),
        (100.0, 0.0),
        (-20.0, 100.0),
        (140.0, 0.0),
    ])
    func remaining(used: Double, expected: Double) {
        #expect(UsageWindow(usedPercentage: used, resetAt: nil).remainingPercentage == expected)
    }

    @Test("Thresholds use remaining, not used")
    func thresholds() {
        #expect(UsageWindow(usedPercentage: 50, resetAt: nil).level == .normal)
        #expect(UsageWindow(usedPercentage: 51, resetAt: nil).level == .attention)
        #expect(UsageWindow(usedPercentage: 80, resetAt: nil).level == .attention)
        #expect(UsageWindow(usedPercentage: 81, resetAt: nil).level == .low)
    }

    @Test("Nil windows stay distinct from zero remaining")
    func nilWindows() {
        let snapshot = UsageSnapshot(provider: .codex, session: nil, weekly: nil, updatedAt: .distantPast)
        #expect(snapshot.session == nil)
        #expect(snapshot.weekly == nil)
        #expect(UsageWindow(usedPercentage: 100, resetAt: nil).remainingPercentage == 0)
    }

    @Test("Updated label and stale boundary")
    func freshness() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(UsageFormatting.updatedText(updatedAt: now - 20, now: now) == "Updated just now")
        #expect(UsageFormatting.updatedText(updatedAt: now - 12 * 60, now: now) == "Updated 12 min ago")
        #expect(UsageFormatting.isStale(updatedAt: now - 901, now: now))
        #expect(!UsageFormatting.isStale(updatedAt: now - 900, now: now))
    }

    @Test("Compact date-time includes both a calendar date and a time")
    func compactDateTime() {
        let value = UsageFormatting.compactDateTime(
            Date(timeIntervalSince1970: 1_777_777_777),
            locale: Locale(identifier: "en_US_POSIX")
        )

        #expect(value.contains("/"))
        #expect(value.contains(":"))
    }

    @Test("Legacy snapshots decode without an account identifier")
    func legacySnapshotCompatibility() throws {
        let legacyJSON = #"{"provider":"codex","session":null,"weekly":null,"updatedAt":0}"#
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: Data(legacyJSON.utf8))
        let legacyEnvelopeJSON = #"{"version":1,"snapshots":[{"provider":"codex","session":null,"weekly":null,"updatedAt":0}]}"#
        let envelope = try SnapshotCoding.decode(Data(legacyEnvelopeJSON.utf8))

        #expect(snapshot.provider == .codex)
        #expect(snapshot.accountIdentifier == nil)
        #expect(snapshot.availableResetCount == nil)
        #expect(envelope.snapshots.first?.availableResetCount == nil)
    }

    @Test("Reset row policy distinguishes missing, zero, positive, and Claude values")
    func resetRowPolicy() {
        #expect(!ResetCreditPresentationPolicy.showsRow(provider: .codex, availableCount: nil))
        #expect(ResetCreditPresentationPolicy.showsRow(provider: .codex, availableCount: 0))
        #expect(!ResetCreditPresentationPolicy.allowsExpansion(provider: .codex, availableCount: 0))
        #expect(ResetCreditPresentationPolicy.showsRow(provider: .codex, availableCount: 2))
        #expect(ResetCreditPresentationPolicy.allowsExpansion(provider: .codex, availableCount: 2))
        #expect(!ResetCreditPresentationPolicy.showsRow(provider: .claude, availableCount: 2))
        #expect(!ResetCreditPresentationPolicy.allowsExpansion(provider: .claude, availableCount: 2))
    }

    @Test("Snapshot reset count round-trips without changing the envelope version")
    func resetCountSnapshotCompatibility() throws {
        let snapshot = UsageSnapshot(
            provider: .codex,
            session: nil,
            weekly: nil,
            availableResetCount: 2,
            updatedAt: .distantPast
        )
        let envelope = SnapshotEnvelope(snapshots: [snapshot])
        let decoded = try SnapshotCoding.decode(SnapshotCoding.encode(envelope))

        #expect(decoded.version == SnapshotEnvelope.currentVersion)
        #expect(decoded.snapshots.first?.availableResetCount == 2)
    }

    @Test("Legacy envelopes default Widget and Watch to the five-hour limit")
    func legacyEnvelopeDisplayLimit() throws {
        let legacyJSON = #"{"version":1,"snapshots":[]}"#
        let envelope = try SnapshotCoding.decode(Data(legacyJSON.utf8))

        #expect(envelope.displayLimit == .fiveHour)
    }

    @Test("Display-limit selection chooses only the requested window")
    func displayLimitWindow() {
        let session = UsageWindow(usedPercentage: 10, resetAt: nil)
        let weekly = UsageWindow(usedPercentage: 20, resetAt: nil)
        let snapshot = UsageSnapshot(
            provider: .claude,
            session: session,
            weekly: weekly,
            updatedAt: .distantPast
        )

        #expect(QuotaDisplayLimit.fiveHour.window(in: snapshot) == session)
        #expect(QuotaDisplayLimit.weekly.window(in: snapshot) == weekly)
    }

    @Test("Account assignment and selected snapshot lookup remain independent")
    func accountSnapshots() {
        let firstID = UUID()
        let secondID = UUID()
        let first = UsageSnapshot(
            provider: .codex,
            accountIdentifier: firstID,
            session: UsageWindow(usedPercentage: 10, resetAt: nil),
            weekly: nil,
            updatedAt: .distantPast
        )
        let second = UsageSnapshot(
            provider: .codex,
            accountIdentifier: secondID,
            session: UsageWindow(usedPercentage: 80, resetAt: nil),
            weekly: nil,
            updatedAt: .distantFuture
        )
        let envelope = SnapshotEnvelope(snapshots: [first, second])

        #expect(envelope.snapshot(for: .codex, accountIdentifier: firstID) == first)
        #expect(envelope.snapshot(for: .codex, accountIdentifier: secondID) == second)
        #expect(envelope.accessLevel == .free)
    }

    @Test("Legacy snapshot envelopes without an entitlement fail closed")
    func legacySnapshotEntitlement() throws {
        let legacyJSON = #"{"version":1,"snapshots":[]}"#
        let envelope = try SnapshotCoding.decode(Data(legacyJSON.utf8))

        #expect(envelope.accessLevel == .free)
        #expect(!envelope.accessLevel.hasProFeatures)
        #expect(!envelope.isAppReviewDemo)
    }

    @Test("App Review Demo marker round-trips without changing access policy")
    func appReviewDemoMarker() throws {
        let selectedCodexAccount = UUID()
        let envelope = SnapshotEnvelope(
            snapshots: [UsageSnapshot(
                provider: .codex,
                accountIdentifier: selectedCodexAccount,
                session: nil,
                weekly: nil,
                updatedAt: .distantPast
            )],
            displayLimit: .weekly,
            accounts: [AccountDisplayMetadata(
                id: selectedCodexAccount,
                provider: .codex,
                ordinal: 2,
                displayName: "Planning"
            )],
            accessLevel: .trial,
            proAccessExpiresAt: .distantFuture,
            isAppReviewDemo: true,
            appReviewDemoDefaultProvider: .codex,
            appReviewDemoSelectedAccountIdentifiers: [.codex: selectedCodexAccount]
        )
        let decoded = try SnapshotCoding.decode(SnapshotCoding.encode(envelope))

        #expect(decoded.isAppReviewDemo)
        #expect(decoded.hasProFeatures())
        #expect(decoded.effectiveDisplayLimit() == .weekly)
        #expect(AppReviewDemoWidgetPolicy.defaultProvider(in: decoded) == .codex)
        #expect(
            AppReviewDemoWidgetPolicy.selectedAccountIdentifier(for: .codex, in: decoded)
                == selectedCodexAccount
        )
        #expect(AppReviewDemoWidgetPolicy.selectedAccountIdentifier(for: .claude, in: decoded) == nil)
    }

    @Test("App Review Demo Widget selection falls back to an account in the published policy")
    func appReviewDemoWidgetSelectionFallback() {
        let freeAccount = UUID()
        let envelope = SnapshotEnvelope(
            snapshots: [],
            accounts: [AccountDisplayMetadata(
                id: freeAccount,
                provider: .codex,
                ordinal: 1,
                displayName: "Studio"
            )],
            accessLevel: .free,
            isAppReviewDemo: true,
            appReviewDemoDefaultProvider: .claude,
            appReviewDemoSelectedAccountIdentifiers: [.codex: UUID(), .claude: UUID()]
        )

        #expect(AppReviewDemoWidgetPolicy.defaultProvider(in: envelope) == .codex)
        #expect(
            AppReviewDemoWidgetPolicy.selectedAccountIdentifier(for: .codex, in: envelope)
                == freeAccount
        )
        #expect(AppReviewDemoWidgetPolicy.selectedAccountIdentifier(for: .claude, in: envelope) == nil)
    }

    @Test("Account display name follows custom, identity, then fallback priority")
    func accountDisplayNamePriority() {
        let identified = ProviderAccount(
            id: UUID(),
            provider: .codex,
            ordinal: 2,
            identityLabel: "sou@example.com"
        )
        let renamed = identified.replacingCustomDisplayName("  仕事用 Codex  ")

        #expect(renamed.displayName(fallback: "Account 2") == "仕事用 Codex")
        #expect(identified.displayName(fallback: "Account 2") == "sou")
        #expect(renamed.replacingCustomDisplayName("  \n").displayName(fallback: "Account 2") == "sou")

        let anonymous = ProviderAccount(id: UUID(), provider: .codex, ordinal: 3)
        #expect(anonymous.displayName(fallback: "Account 3") == "Account 3")
    }

    @Test("Legacy account JSON decodes without a custom display name")
    func legacyAccountCompatibility() throws {
        let id = UUID()
        let legacyJSON = #"{"id":"\#(id.uuidString)","provider":"codex","ordinal":1,"identityLabel":"old@example.com"}"#
        let account = try JSONDecoder().decode(ProviderAccount.self, from: Data(legacyJSON.utf8))

        #expect(account.id == id)
        #expect(account.identityLabel == "old@example.com")
        #expect(account.customDisplayName == nil)
    }

    @Test("Distinct account identities survive persistence and a missing refresh identity")
    func accountIdentityPersistence() throws {
        let first = ProviderAccount(id: UUID(), provider: .codex, ordinal: 1, identityLabel: "one@example.com")
        let second = ProviderAccount(id: UUID(), provider: .codex, ordinal: 2, identityLabel: "Two Person")
        let restored = try JSONDecoder().decode(
            [ProviderAccount].self,
            from: JSONEncoder().encode([first, second])
        )

        #expect(restored.map { $0.displayName(fallback: "fallback") } == ["one", "Two Person"])
        #expect(restored[0].replacingIdentityLabel(nil).identityLabel == "one@example.com")
    }

    @Test("Claude OAuth token account decodes its stable ID and email identity")
    func claudeOAuthAccountIdentity() throws {
        struct TokenMetadata: Decodable {
            let account: ClaudeOAuthAccount
            let organization: ClaudeOAuthOrganization
        }

        let metadata = try JSONDecoder().decode(TokenMetadata.self, from: Data(#"""
        {
          "account": {
            "uuid": "account-123",
            "email_address": " claude@example.com "
          },
          "organization": {
            "uuid": "organization-456"
          }
        }
        """#.utf8))

        #expect(metadata.account.uuid == "account-123")
        #expect(metadata.account.identityLabel == "claude@example.com")
        #expect(metadata.organization.uuid == "organization-456")
    }

    @Test("Claude OAuth name takes priority over its email")
    func claudeOAuthAccountNamePriority() throws {
        let account = try JSONDecoder().decode(ClaudeOAuthAccount.self, from: Data(#"""
        {
          "uuid": "account-123",
          "name": " Song Labs ",
          "email_address": "claude@example.com"
        }
        """#.utf8))

        #expect(account.identityLabel == "Song Labs")
    }

    @Test("Watch selection keeps numbered order, shifts after removal, and rejects a third account")
    func watchAccountSelectionLimit() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let firstTwo = WatchAccountSelection.adding(
            secondID,
            to: WatchAccountSelection.adding(firstID, to: [])!
        )!

        #expect(firstTwo == [firstID, secondID])
        #expect(WatchAccountSelection.position(of: firstID, in: firstTwo) == 1)
        #expect(WatchAccountSelection.position(of: secondID, in: firstTwo) == 2)
        #expect(WatchAccountSelection.position(of: thirdID, in: firstTwo) == nil)
        #expect(WatchAccountSelection.adding(thirdID, to: firstTwo) == nil)
        #expect(WatchAccountSelection.normalized([firstID, firstID, secondID, thirdID]) == [firstID, secondID])

        let shifted = WatchAccountSelection.removing(firstID, from: firstTwo)
        #expect(shifted == [secondID])
        #expect(WatchAccountSelection.position(of: secondID, in: shifted) == 1)

        let appended = WatchAccountSelection.adding(thirdID, to: shifted)
        #expect(appended == [secondID, thirdID])
        #expect(WatchAccountSelection.position(of: thirdID, in: appended ?? []) == 2)
    }

    @Test("Watch refresh scope follows current entitlement")
    func watchRefreshScope() {
        let firstID = UUID()
        let secondID = UUID()
        let accounts = [firstID, secondID]
        let selection = [secondID]

        #expect(WatchRefreshScope.accountIdentifiers(
            accounts: accounts,
            selectedAccountIdentifiers: selection,
            hasProFeatures: false
        ) == [firstID])
        #expect(WatchRefreshScope.accountIdentifiers(
            accounts: accounts,
            selectedAccountIdentifiers: selection,
            hasProFeatures: true
        ) == [secondID])

        let expiredAccess = AccessLevel.resolve(
            hasLifetimePurchase: false,
            trialPurchaseDate: Date(timeIntervalSince1970: 0),
            trialDuration: 100,
            now: Date(timeIntervalSince1970: 101)
        )
        #expect(expiredAccess == .free)
        #expect(WatchRefreshScope.accountIdentifiers(
            accounts: accounts,
            selectedAccountIdentifiers: selection,
            hasProFeatures: expiredAccess.hasProFeatures
        ) == [firstID])
    }

    @Test("Removing an account preserves Trial entitlement metadata")
    func removingAccountPreservesEntitlement() {
        let removedID = UUID()
        let remainingID = UUID()
        let expiry = Date(timeIntervalSince1970: 10_000)
        let envelope = SnapshotEnvelope(
            snapshots: [
                UsageSnapshot(provider: .codex, accountIdentifier: removedID, session: nil, weekly: nil, updatedAt: .distantPast),
                UsageSnapshot(provider: .claude, accountIdentifier: remainingID, session: nil, weekly: nil, updatedAt: .distantPast),
            ],
            accounts: [
                AccountDisplayMetadata(id: removedID, provider: .codex, ordinal: 1, displayName: "removed"),
                AccountDisplayMetadata(id: remainingID, provider: .claude, ordinal: 1, displayName: "remaining"),
            ],
            watchAccountIdentifiers: [removedID, remainingID],
            accessLevel: .trial,
            proAccessExpiresAt: expiry
        )

        let remaining = envelope.removingAccount(removedID)
        #expect(remaining.snapshots.map(\.accountIdentifier) == [remainingID])
        #expect(remaining.accounts.map(\.id) == [remainingID])
        #expect(remaining.watchAccountIdentifiers == [remainingID])
        #expect(remaining.accessLevel == .trial)
        #expect(remaining.proAccessExpiresAt == expiry)
    }

    @Test("One-account Watch presentation keeps independent 5H and Weekly reset dates")
    func oneWatchAccountPresentation() {
        let accountID = UUID()
        let sessionReset = Date(timeIntervalSince1970: 10_000)
        let weeklyReset = Date(timeIntervalSince1970: 70_000)
        let snapshot = UsageSnapshot(
            provider: .codex,
            accountIdentifier: accountID,
            session: UsageWindow(usedPercentage: 18, resetAt: sessionReset),
            weekly: UsageWindow(usedPercentage: 36, resetAt: weeklyReset),
            updatedAt: Date(timeIntervalSince1970: 5_000)
        )
        let envelope = SnapshotEnvelope(
            snapshots: [snapshot],
            accounts: [AccountDisplayMetadata(
                id: accountID,
                provider: .codex,
                ordinal: 1,
                displayName: "sou"
            )],
            watchAccountIdentifiers: [accountID]
        )

        #expect(envelope.watchAccountPresentations.count == 1)
        #expect(envelope.watchAccountPresentations[0].displayName == "sou")
        #expect(envelope.watchAccountPresentations[0].snapshot?.session?.resetAt == sessionReset)
        #expect(envelope.watchAccountPresentations[0].snapshot?.weekly?.resetAt == weeklyReset)
        #expect(sessionReset != weeklyReset)
    }

    @Test("Two-account Watch presentation follows the cross-provider selection order")
    func twoWatchAccountPresentation() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let accounts = [
            AccountDisplayMetadata(id: firstID, provider: .codex, ordinal: 1, displayName: "sou"),
            AccountDisplayMetadata(id: secondID, provider: .codex, ordinal: 2, displayName: "account2"),
            AccountDisplayMetadata(id: thirdID, provider: .claude, ordinal: 1, displayName: "song"),
        ]
        let snapshots = accounts.map { account in
            UsageSnapshot(
                provider: account.provider,
                accountIdentifier: account.id,
                session: UsageWindow(usedPercentage: 10, resetAt: nil),
                weekly: UsageWindow(usedPercentage: 20, resetAt: nil),
                updatedAt: .distantPast
            )
        }
        let envelope = SnapshotEnvelope(
            snapshots: snapshots,
            accounts: accounts,
            watchAccountIdentifiers: [thirdID, secondID],
            accessLevel: .pro
        )

        #expect(envelope.accountPresentations.count == 3)
        #expect(envelope.watchAccountPresentations.map(\.displayName) == ["song", "account2"])
        #expect(envelope.watchAccountPresentations.map(\.provider) == [.claude, .codex])
    }

    @Test("A missing second Watch account safely produces a one-account presentation")
    func missingSecondWatchAccountPresentation() {
        let firstID = UUID()
        let missingID = UUID()
        let envelope = SnapshotEnvelope(
            snapshots: [],
            accounts: [AccountDisplayMetadata(
                id: firstID,
                provider: .codex,
                ordinal: 1,
                displayName: "sou"
            )],
            watchAccountIdentifiers: [firstID, missingID],
            accessLevel: .pro
        )

        #expect(envelope.watchAccountPresentations.map(\.accountIdentifier) == [firstID])
    }

    @Test("Free Watch presentation ignores saved multi-account selection")
    func freeWatchUsesFirstAccountOnly() {
        let firstID = UUID()
        let secondID = UUID()
        let accounts = [
            AccountDisplayMetadata(id: firstID, provider: .codex, ordinal: 1, displayName: "first"),
            AccountDisplayMetadata(id: secondID, provider: .claude, ordinal: 1, displayName: "second"),
        ]
        let envelope = SnapshotEnvelope(
            snapshots: [],
            displayLimit: .weekly,
            accounts: accounts,
            watchAccountIdentifiers: [secondID, firstID],
            accessLevel: .free
        )

        #expect(envelope.watchAccountPresentations.map(\.accountIdentifier) == [firstID])
        #expect(envelope.effectiveDisplayLimit() == .fiveHour)
    }

    @Test("An explicit empty Watch selection does not silently select an account")
    func emptyWatchAccountSelection() {
        let accountID = UUID()
        let envelope = SnapshotEnvelope(
            snapshots: [UsageSnapshot(
                provider: .codex,
                accountIdentifier: accountID,
                session: nil,
                weekly: nil,
                updatedAt: .distantPast
            )],
            accounts: [AccountDisplayMetadata(
                id: accountID,
                provider: .codex,
                ordinal: 1,
                displayName: "sou"
            )],
            watchAccountIdentifiers: [],
            accessLevel: .pro
        )

        #expect(envelope.watchAccountPresentations.isEmpty)
    }

    @Test("Shared watch cache round-trips every supported snapshot combination", arguments: [
        [AIProvider.codex],
        [AIProvider.claude],
        [AIProvider.codex, AIProvider.claude],
    ])
    func sharedWatchCacheRoundTrip(providers: [AIProvider]) throws {
        let suiteName = "QuotaGlanceCoreTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let accountIdentifier = UUID()
        let snapshots = providers.enumerated().map { index, provider in
            UsageSnapshot(
                provider: provider,
                accountIdentifier: index == 0 ? accountIdentifier : nil,
                session: UsageWindow(usedPercentage: Double(20 + index), resetAt: nil),
                weekly: UsageWindow(usedPercentage: Double(40 + index), resetAt: nil),
                updatedAt: Date(timeIntervalSince1970: Double(1_000 + index))
            )
        }
        let account = AccountDisplayMetadata(
            id: accountIdentifier,
            provider: providers[0],
            ordinal: 1,
            displayName: "account"
        )
        let envelope = SnapshotEnvelope(
            snapshots: snapshots,
            displayLimit: .weekly,
            accounts: [account],
            watchAccountIdentifiers: [accountIdentifier]
        )
        let cache = SharedWatchSnapshotCache(suiteName: suiteName)

        #expect(cache.isAvailable)
        #expect(cache.load() == nil)
        #expect(cache.save(envelope))
        #expect(cache.load() == envelope)
        #expect(cache.load()?.displayLimit == .weekly)
        #expect(cache.load()?.snapshots.first?.accountIdentifier == accountIdentifier)
        #expect(cache.load()?.accounts == [account])
        #expect(cache.load()?.watchAccountIdentifiers == [accountIdentifier])
    }
}

@Suite("Refresh interval")
struct RefreshIntervalTests {
    @Test("All discrete options map to the expected durations")
    func optionDurations() {
        #expect(AutomaticRefreshInterval.allCases == [
            .disabled,
            .fifteenMinutes,
            .thirtyMinutes,
            .oneHour,
            .twoHours,
            .fourHours,
        ])
        #expect(AutomaticRefreshInterval.allCases.map(\.timeInterval) == [
            nil,
            Optional<TimeInterval>(15 * 60),
            Optional<TimeInterval>(30 * 60),
            Optional<TimeInterval>(60 * 60),
            Optional<TimeInterval>(2 * 60 * 60),
            Optional<TimeInterval>(4 * 60 * 60),
        ])
    }

    @Test("Default is four hours")
    func defaultInterval() {
        let interval = AutomaticRefreshInterval.defaultInterval

        #expect(interval == .fourHours)
        #expect(interval.timeInterval == Optional<TimeInterval>(14_400))
    }

    @Test("Free is fixed at four hours while Trial and Pro use the stored interval")
    func effectiveIntervalFollowsAccessLevel() {
        let stored = AutomaticRefreshInterval.fifteenMinutes

        #expect(stored.effective(for: .free) == .fixedFreeInterval)
        #expect(stored.effective(for: .free).timeInterval == Optional<TimeInterval>(14_400))
        #expect(stored.effective(for: .trial) == stored)
        #expect(stored.effective(for: .pro) == stored)

        let disabled = AutomaticRefreshInterval.disabled
        #expect(disabled.effective(for: .free) == .fourHours)
        #expect(disabled.effective(for: .trial) == .disabled)
        #expect(disabled.effective(for: .pro) == .disabled)
    }

    @Test("Automatic refresh uses the successful-update boundary")
    func refreshBoundary() {
        let interval = AutomaticRefreshInterval.fifteenMinutes
        let lastUpdate = Date(timeIntervalSince1970: 1_000)

        #expect(!interval.shouldRefresh(
            lastSuccessfulUpdate: lastUpdate,
            now: lastUpdate.addingTimeInterval(899)
        ))
        #expect(interval.shouldRefresh(
            lastSuccessfulUpdate: lastUpdate,
            now: lastUpdate.addingTimeInterval(900)
        ))
        #expect(interval.shouldRefresh(lastSuccessfulUpdate: nil, now: lastUpdate))
    }

    @Test("A failed automatic attempt prevents a tight retry loop")
    func automaticAttemptBoundary() {
        let interval = AutomaticRefreshInterval.fifteenMinutes
        let staleUpdate = Date(timeIntervalSince1970: 1_000)
        let lastAttempt = Date(timeIntervalSince1970: 10_000)

        #expect(!interval.shouldRefresh(
            lastSuccessfulUpdate: staleUpdate,
            lastRefreshAttempt: lastAttempt,
            now: lastAttempt.addingTimeInterval(899)
        ))
        #expect(interval.shouldRefresh(
            lastSuccessfulUpdate: staleUpdate,
            lastRefreshAttempt: lastAttempt,
            now: lastAttempt.addingTimeInterval(900)
        ))
    }

    @Test("Foreground and background schedule dates use the selected interval")
    func scheduleDates() {
        let now = Date(timeIntervalSince1970: 20_000)
        let lastUpdate = now.addingTimeInterval(-5 * 60)

        #expect(AutomaticRefreshInterval.fifteenMinutes.nextRefreshDate(
            lastSuccessfulUpdate: lastUpdate,
            now: now
        ) == now.addingTimeInterval(10 * 60))
        #expect(AutomaticRefreshInterval.fifteenMinutes.earliestBackgroundBeginDate(
            from: now
        ) == now.addingTimeInterval(15 * 60))
        #expect(AutomaticRefreshInterval.disabled.nextRefreshDate(
            lastSuccessfulUpdate: nil,
            now: now
        ) == nil)
        #expect(AutomaticRefreshInterval.disabled.earliestBackgroundBeginDate(from: now) == nil)
        #expect(AutomaticRefreshInterval.disabled.shouldRefresh(
            lastSuccessfulUpdate: nil,
            force: true,
            now: now
        ))
    }

    @Test("Legacy minute and hour values migrate without shortening the interval")
    func legacyMigration() {
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
            #expect(AutomaticRefreshInterval.migratingLegacy(value: value, unit: "minute") == expected)
        }

        let hourCases: [(Int, AutomaticRefreshInterval)] = [
            (0, .disabled),
            (1, .oneHour),
            (2, .twoHours),
            (3, .fourHours),
            (4, .fourHours),
            (8, .fourHours),
        ]
        for (value, expected) in hourCases {
            #expect(AutomaticRefreshInterval.migratingLegacy(value: value, unit: "hour") == expected)
        }
    }

    @Test("Preferences default, persist, and migrate only when the new format is absent")
    func preferencesPersistence() {
        let suiteName = "RefreshIntervalTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AutomaticRefreshPreferences.load(from: defaults) == .fourHours)
        #expect(defaults.string(forKey: AutomaticRefreshPreferences.intervalKey) == AutomaticRefreshInterval.fourHours.rawValue)

        AutomaticRefreshPreferences.save(.fifteenMinutes, to: defaults)
        #expect(AutomaticRefreshPreferences.load(from: defaults) == .fifteenMinutes)
        #expect(AutomaticRefreshPreferences.load(from: defaults).effective(for: .free) == .fourHours)
        #expect(AutomaticRefreshPreferences.load(from: defaults).effective(for: .pro) == .fifteenMinutes)

        defaults.removeObject(forKey: AutomaticRefreshPreferences.intervalKey)
        defaults.set(90, forKey: AutomaticRefreshPreferences.legacyValueKey)
        defaults.set("minute", forKey: AutomaticRefreshPreferences.legacyUnitKey)
        #expect(AutomaticRefreshPreferences.load(from: defaults) == .twoHours)
        #expect(defaults.string(forKey: AutomaticRefreshPreferences.intervalKey) == AutomaticRefreshInterval.twoHours.rawValue)

        defaults.set(5, forKey: AutomaticRefreshPreferences.legacyValueKey)
        #expect(AutomaticRefreshPreferences.load(from: defaults) == .twoHours)

        AutomaticRefreshPreferences.save(.disabled, to: defaults)
        #expect(AutomaticRefreshPreferences.load(from: defaults).effective(for: .free) == .fourHours)
        #expect(AutomaticRefreshPreferences.load(from: defaults) == .disabled)
        #expect(AutomaticRefreshPreferences.load(from: defaults).effective(for: .pro) == .disabled)
    }

    @Test("Other Pro-only selections keep stored values while Free uses fixed defaults")
    func otherProOnlySelections() {
        let storedQuota = QuotaDisplayLimit.weekly
        #expect(storedQuota.effective(for: .free) == .fiveHour)
        #expect(storedQuota.effective(for: .trial) == .weekly)
        #expect(storedQuota.effective(for: .pro) == .weekly)

        let first = UUID()
        let second = UUID()
        let third = UUID()
        #expect(WatchAccountSelection.initial(
            accountIdentifiers: [first, second, third],
            legacySelectedAccountIdentifiers: []
        ) == [first])
        let storedWatchSelection = WatchAccountSelection.initial(
            accountIdentifiers: [first, second, third],
            legacySelectedAccountIdentifiers: [second, third]
        )
        #expect(storedWatchSelection == [second, third])
        #expect(WatchRefreshScope.accountIdentifiers(
            accounts: [first, second, third],
            selectedAccountIdentifiers: storedWatchSelection,
            hasProFeatures: false
        ) == [first])
        #expect(storedWatchSelection == [second, third])
        #expect(WatchRefreshScope.accountIdentifiers(
            accounts: [first, second, third],
            selectedAccountIdentifiers: storedWatchSelection,
            hasProFeatures: true
        ) == [second, third])
    }
}
