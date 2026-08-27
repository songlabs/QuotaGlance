import Foundation
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
        XCTAssertEqual(AutomaticRefreshInterval.allCases.map(\.timeInterval), [
            nil,
            15 * 60,
            30 * 60,
            60 * 60,
            2 * 60 * 60,
            4 * 60 * 60,
        ])
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
}
