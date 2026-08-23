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
        #expect(snapshot.updatedAt == updatedAt)
    }

    @Test("Claude fixture maps utilization as used percentage")
    func claudeFixture() throws {
        let snapshot = try UsageResponseDecoder.decodeClaude(fixture("claude-usage"), now: .distantPast)

        #expect(snapshot.provider == .claude)
        #expect(snapshot.session?.remainingPercentage == 48)
        #expect(snapshot.weekly?.remainingPercentage == 63)
        #expect(snapshot.session?.resetAt != nil)
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
}
