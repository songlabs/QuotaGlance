import Foundation

public enum UsageResponseDecoder {
    public static func decodeCodex(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        let response: CodexUsageResponse
        do {
            response = try configuredDecoder().decode(CodexUsageResponse.self, from: data)
        } catch {
            throw UsageProviderError.schemaChanged
        }

        guard let limits = response.rateLimit else {
            throw UsageProviderError.schemaChanged
        }

        let windows = [limits.primaryWindow, limits.secondaryWindow].compactMap { $0 }
        guard !windows.isEmpty else {
            throw UsageProviderError.schemaChanged
        }

        let session = windows
            .filter { abs($0.limitWindowSeconds - 18_000) <= 3_600 }
            .min { abs($0.limitWindowSeconds - 18_000) < abs($1.limitWindowSeconds - 18_000) }
            .map(usageWindow)

        let weekly = windows
            .filter { abs($0.limitWindowSeconds - 604_800) <= 86_400 }
            .min { abs($0.limitWindowSeconds - 604_800) < abs($1.limitWindowSeconds - 604_800) }
            .map(usageWindow)

        guard session != nil || weekly != nil else {
            throw UsageProviderError.schemaChanged
        }

        return UsageSnapshot(
            provider: .codex,
            session: session,
            weekly: weekly,
            availableResetCount: response.rateLimitResetCredits?.availableCount,
            updatedAt: now
        )
    }

    public static func decodeCodexResetCredits(_ data: Data) throws -> CodexResetCreditDetails {
        do {
            return try configuredDecoder().decode(CodexResetCreditDetails.self, from: data)
        } catch {
            throw UsageProviderError.schemaChanged
        }
    }

    public static func decodeClaude(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        let response: ClaudeUsageResponse
        do {
            response = try configuredDecoder().decode(ClaudeUsageResponse.self, from: data)
        } catch {
            throw UsageProviderError.schemaChanged
        }

        let sessionSource = response.fiveHour ?? response.limits?.first { $0.kind == "session" }.map(ClaudeWindow.init)
        let weeklySource = response.sevenDay ?? response.limits?.first { $0.kind == "weekly_all" }.map(ClaudeWindow.init)

        let session = sessionSource.map { UsageWindow(usedPercentage: $0.utilization, resetAt: $0.resetsAt) }
        let weekly = weeklySource.map { UsageWindow(usedPercentage: $0.utilization, resetAt: $0.resetsAt) }

        guard session != nil || weekly != nil else {
            throw UsageProviderError.schemaChanged
        }

        return UsageSnapshot(provider: .claude, session: session, weekly: weekly, updatedAt: now)
    }

    private static func usageWindow(_ source: CodexWindow) -> UsageWindow {
        UsageWindow(
            usedPercentage: source.usedPercent,
            resetAt: source.resetAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private static func configuredDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = parseISO8601(string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
        }
        return decoder
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        return wholeSeconds.date(from: value)
    }
}

private struct CodexUsageResponse: Decodable {
    let rateLimit: CodexRateLimit?
    let rateLimitResetCredits: CodexResetCreditSummary?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
        case rateLimitResetCredits = "rate_limit_reset_credits"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rateLimit = try container.decodeIfPresent(CodexRateLimit.self, forKey: .rateLimit)
        rateLimitResetCredits = try? container.decodeIfPresent(
            CodexResetCreditSummary.self,
            forKey: .rateLimitResetCredits
        )
    }
}

private struct CodexResetCreditSummary: Decodable {
    let availableCount: Int?

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        availableCount = try? container.decode(Int.self, forKey: .availableCount)
    }
}

private struct CodexRateLimit: Decodable {
    let primaryWindow: CodexWindow?
    let secondaryWindow: CodexWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct CodexWindow: Decodable {
    let usedPercent: Double
    let limitWindowSeconds: Int
    let resetAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }
}

private struct ClaudeUsageResponse: Decodable {
    let fiveHour: ClaudeWindow?
    let sevenDay: ClaudeWindow?
    let limits: [ClaudeLimit]?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case limits
    }
}

private struct ClaudeWindow: Decodable {
    let utilization: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(_ limit: ClaudeLimit) {
        utilization = limit.percent
        resetsAt = limit.resetsAt
    }
}

private struct ClaudeLimit: Decodable {
    let kind: String
    let percent: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case kind
        case percent
        case resetsAt = "resets_at"
    }
}
