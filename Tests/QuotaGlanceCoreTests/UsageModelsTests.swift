import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Remaining percentage")
struct UsageModelsTests {
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

    @Test("Legacy snapshots decode without an account identifier")
    func legacySnapshotCompatibility() throws {
        let legacyJSON = #"{"provider":"codex","session":null,"weekly":null,"updatedAt":0}"#
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: Data(legacyJSON.utf8))

        #expect(snapshot.provider == .codex)
        #expect(snapshot.accountIdentifier == nil)
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
        #expect(identified.displayName(fallback: "Account 2") == "sou@example.com")
        #expect(renamed.replacingCustomDisplayName("  \n").displayName(fallback: "Account 2") == "sou@example.com")

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

        #expect(restored.map { $0.displayName(fallback: "fallback") } == ["one@example.com", "Two Person"])
        #expect(restored[0].replacingIdentityLabel(nil).identityLabel == "one@example.com")
    }
}
