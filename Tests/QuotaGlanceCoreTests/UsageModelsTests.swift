import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Remaining percentage")
struct UsageModelsTests {
    @Test("Access resolves purchased, active trial, and expired trial states")
    func accessResolution() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(AccessLevel.resolve(isPurchased: true, trialEndsAt: now, now: now) == .pro)
        #expect(AccessLevel.resolve(isPurchased: false, trialEndsAt: now.addingTimeInterval(1), now: now) == .trial)
        #expect(AccessLevel.resolve(isPurchased: false, trialEndsAt: now, now: now) == .free)
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

        #expect(snapshot.provider == .codex)
        #expect(snapshot.accountIdentifier == nil)
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

    @Test("Watch selection keeps order, rejects a third account, and supports two accounts from one provider")
    func watchAccountSelectionLimit() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let firstTwo = WatchAccountSelection.adding(
            secondID,
            to: WatchAccountSelection.adding(firstID, to: [])!
        )!

        #expect(firstTwo == [firstID, secondID])
        #expect(WatchAccountSelection.adding(thirdID, to: firstTwo) == nil)
        #expect(WatchAccountSelection.normalized([firstID, firstID, secondID, thirdID]) == [firstID, secondID])
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
            watchAccountIdentifiers: [thirdID, secondID]
        )

        #expect(envelope.accountPresentations.count == 3)
        #expect(envelope.watchAccountPresentations.map(\.displayName) == ["song", "account2"])
        #expect(envelope.watchAccountPresentations.map(\.provider) == [.claude, .codex])
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
            watchAccountIdentifiers: []
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
    @Test("Default is 30 minutes")
    func defaultInterval() {
        let interval = RefreshInterval.defaultInterval

        #expect(interval.value == 30)
        #expect(interval.unit == .minute)
        #expect(interval.timeInterval == Optional<TimeInterval>(1_800))
    }

    @Test("Minute and hour ranges match settings pickers")
    func validRanges() {
        #expect(Array(RefreshIntervalUnit.minute.valueRange) == Array(0...59))
        #expect(Array(RefreshIntervalUnit.hour.valueRange) == Array(0...23))
    }

    @Test("Changing to hours clamps an invalid minute value")
    func unitChangeClampsValue() {
        let minutes = RefreshInterval(value: 59, unit: .minute)
        let hours = minutes.replacingUnit(.hour)

        #expect(hours.value == 23)
        #expect(hours.unit == .hour)
        #expect(hours.timeInterval == Optional<TimeInterval>(82_800))
    }

    @Test("Zero disables automatic refresh for both units")
    func zeroDisablesAutomaticRefresh() {
        let now = Date(timeIntervalSince1970: 10_000)

        for unit in RefreshIntervalUnit.allCases {
            let interval = RefreshInterval(value: 0, unit: unit)
            #expect(interval.timeInterval == nil)
            #expect(!interval.shouldRefresh(lastSuccessfulUpdate: nil, now: now))
            #expect(!interval.shouldRefresh(lastSuccessfulUpdate: .distantPast, now: now))
            #expect(interval.shouldRefresh(lastSuccessfulUpdate: nil, force: true, now: now))
        }
    }

    @Test("Automatic refresh uses the successful-update boundary")
    func refreshBoundary() {
        let interval = RefreshInterval(value: 10, unit: .minute)
        let lastUpdate = Date(timeIntervalSince1970: 1_000)

        #expect(!interval.shouldRefresh(
            lastSuccessfulUpdate: lastUpdate,
            now: lastUpdate.addingTimeInterval(599)
        ))
        #expect(interval.shouldRefresh(
            lastSuccessfulUpdate: lastUpdate,
            now: lastUpdate.addingTimeInterval(600)
        ))
        #expect(interval.shouldRefresh(lastSuccessfulUpdate: nil, now: lastUpdate))
    }

    @Test("Two hours converts to seconds and gates refresh")
    func hoursRefreshBoundary() {
        let interval = RefreshInterval(value: 2, unit: .hour)
        let lastUpdate = Date(timeIntervalSince1970: 1_000)

        #expect(interval.timeInterval == Optional<TimeInterval>(7_200))
        #expect(!interval.shouldRefresh(
            lastSuccessfulUpdate: lastUpdate,
            now: lastUpdate.addingTimeInterval(7_199)
        ))
        #expect(interval.shouldRefresh(
            lastSuccessfulUpdate: lastUpdate,
            now: lastUpdate.addingTimeInterval(7_200)
        ))
    }

    @Test("Preferences default, persist, and normalize values")
    func preferencesPersistence() {
        let suiteName = "RefreshIntervalTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(RefreshIntervalPreferences.load(from: defaults) == .defaultInterval)

        let saved = RefreshInterval(value: 30, unit: .minute)
        RefreshIntervalPreferences.save(saved, to: defaults)
        #expect(RefreshIntervalPreferences.load(from: defaults) == saved)

        defaults.set(59, forKey: RefreshIntervalPreferences.valueKey)
        defaults.set(RefreshIntervalUnit.hour.rawValue, forKey: RefreshIntervalPreferences.unitKey)
        #expect(RefreshIntervalPreferences.load(from: defaults) == RefreshInterval(value: 23, unit: .hour))

        defaults.removeObject(forKey: RefreshIntervalPreferences.valueKey)
        #expect(RefreshIntervalPreferences.load(from: defaults) == .defaultInterval)
    }
}
