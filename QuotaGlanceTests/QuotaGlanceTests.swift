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
}
