import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Provider response decoders")
struct ProviderDecoderTests {
    @Test("Codex fixture maps 5h and weekly used percentages")
    func codexFixture() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_000)
        let snapshot = try UsageResponseDecoder.decodeCodex(fixture("codex-usage"), now: updatedAt)

        #expect(snapshot.provider == .codex)
        #expect(snapshot.session?.remainingPercentage == 72)
        #expect(snapshot.weekly?.remainingPercentage == 41)
        #expect(snapshot.session?.resetAt == Date(timeIntervalSince1970: 1_787_509_920))
        #expect(snapshot.weekly?.resetAt == Date(timeIntervalSince1970: 1_787_871_605))
        #expect(snapshot.availableResetCount == 2)
        #expect(snapshot.updatedAt == updatedAt)
    }

    @Test("Codex reset count preserves zero")
    func codexZeroResetCount() throws {
        let snapshot = try UsageResponseDecoder.decodeCodex(codexUsageJSON(
            resetCreditObject: #"{"available_count":0}"#
        ))

        #expect(snapshot.availableResetCount == 0)
        #expect(snapshot.session?.remainingPercentage == 75)
        #expect(snapshot.weekly?.remainingPercentage == 50)
    }

    @Test("Codex usage remains decodable when reset count is absent")
    func codexMissingResetCount() throws {
        let missingObject = try UsageResponseDecoder.decodeCodex(codexUsageJSON())
        let missingCount = try UsageResponseDecoder.decodeCodex(codexUsageJSON(
            resetCreditObject: "{}"
        ))
        let malformedCount = try UsageResponseDecoder.decodeCodex(codexUsageJSON(
            resetCreditObject: #"{"available_count":"unexpected"}"#
        ))

        #expect(missingObject.availableResetCount == nil)
        #expect(missingCount.availableResetCount == nil)
        #expect(malformedCount.availableResetCount == nil)
        #expect(missingObject.session?.resetAt == Date(timeIntervalSince1970: 1_000))
        #expect(missingObject.weekly?.resetAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test("Codex reset details decode titles and optional expirations")
    func codexResetDetails() throws {
        let details = try UsageResponseDecoder.decodeCodexResetCredits(Data(#"""
        {
          "credits": [
            {
              "id": "later",
              "reset_type": "codex_rate_limits",
              "status": "available",
              "granted_at": "2026-09-01T00:00:00Z",
              "expires_at": "2026-10-04T09:39:00Z",
              "title": "Full reset"
            },
            {
              "id": "no-expiration",
              "reset_type": "codex_rate_limits",
              "status": "available",
              "granted_at": "2026-09-02T00:00:00Z",
              "expires_at": null
            },
            {
              "id": "earlier",
              "reset_type": "codex_rate_limits",
              "status": "AVAILABLE",
              "granted_at": "2026-09-03T00:00:00Z",
              "expires_at": "2026-09-21T06:31:00Z",
              "title": "  Weekly and 5h reset  "
            },
            {
              "id": "redeemed",
              "reset_type": "codex_rate_limits",
              "status": "redeemed",
              "granted_at": "2026-08-01T00:00:00Z",
              "expires_at": "2026-09-10T00:00:00Z",
              "title": "Already used"
            }
          ],
          "available_count": 3,
          "total_earned_count": 4
        }
        """#.utf8))

        #expect(details.credits.count == 4)
        #expect(details.credits[0].title == "Full reset")
        #expect(details.credits[1].title == nil)
        #expect(details.credits[1].expiresAt == nil)
        #expect(details.credits[2].providerTitle == "Weekly and 5h reset")

        let sorted = ResetCreditPresentationPolicy.sortedAvailableCredits(in: details)
        #expect(sorted.map(\.id) == ["earlier", "later", "no-expiration"])
        #expect(
            ResetCreditPresentationPolicy.nearestExpiration(in: details)
                == ISO8601DateFormatter().date(from: "2026-09-21T06:31:00Z")
        )
    }

    @Test("Claude fixture maps utilization as used percentage")
    func claudeFixture() throws {
        let snapshot = try UsageResponseDecoder.decodeClaude(fixture("claude-usage"), now: .distantPast)

        #expect(snapshot.provider == .claude)
        #expect(snapshot.session?.remainingPercentage == 48)
        #expect(snapshot.weekly?.remainingPercentage == 63)
        #expect(snapshot.session?.resetAt != nil)
        #expect(snapshot.weekly?.resetAt == ISO8601DateFormatter().date(from: "2026-08-29T09:00:00Z"))
        #expect(snapshot.availableResetCount == nil)
    }

    @Test("Missing provider windows is a schema error")
    func missingWindows() {
        #expect(throws: UsageProviderError.schemaChanged) {
            try UsageResponseDecoder.decodeCodex(Data(#"{"plan_type":"plus","rate_limit":null}"#.utf8))
        }
        #expect(throws: UsageProviderError.schemaChanged) {
            try UsageResponseDecoder.decodeClaude(Data("{}".utf8))
        }
    }

    @Test("Claude limits-array schema remains supported")
    func claudeLimitsArray() throws {
        let json = #"{"limits":[{"kind":"session","group":"session","percent":12,"resets_at":null},{"kind":"weekly_all","group":"weekly","percent":34,"resets_at":null}]}"#
        let snapshot = try UsageResponseDecoder.decodeClaude(Data(json.utf8))
        #expect(snapshot.session?.remainingPercentage == 88)
        #expect(snapshot.weekly?.remainingPercentage == 66)
        #expect(snapshot.session?.resetAt == nil)
    }

    private func fixture(_ name: String) -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try! Data(contentsOf: url)
    }

    private func codexUsageJSON(resetCreditObject: String? = nil) -> Data {
        let resetCreditField = resetCreditObject.map {
            #", "rate_limit_reset_credits": \#($0)"#
        } ?? ""
        return Data(#"""
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
          }\#(resetCreditField)
        }
        """#.utf8)
    }
}
