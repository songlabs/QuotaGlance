import Foundation

public struct UsageWindow: Codable, Equatable, Sendable {
    public let usedPercentage: Double
    public let resetAt: Date?

    public init(usedPercentage: Double, resetAt: Date?) {
        self.usedPercentage = usedPercentage
        self.resetAt = resetAt
    }

    public var remainingPercentage: Double {
        min(100, max(0, 100 - usedPercentage))
    }

    public var roundedRemainingPercentage: Int {
        Int(remainingPercentage.rounded())
    }

    public var level: RemainingLevel {
        switch remainingPercentage {
        case 50...: .normal
        case 20..<50: .attention
        default: .low
        }
    }
}

public enum RemainingLevel: String, Codable, Equatable, Sendable {
    case normal
    case attention
    case low
}

public struct UsageSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let provider: AIProvider
    public let session: UsageWindow?
    public let weekly: UsageWindow?
    public let updatedAt: Date

    public init(
        provider: AIProvider,
        session: UsageWindow?,
        weekly: UsageWindow?,
        updatedAt: Date
    ) {
        self.provider = provider
        self.session = session
        self.weekly = weekly
        self.updatedAt = updatedAt
    }

    public var id: AIProvider { provider }
}

public struct SnapshotEnvelope: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let snapshots: [UsageSnapshot]

    public init(version: Int = Self.currentVersion, snapshots: [UsageSnapshot]) {
        self.version = version
        self.snapshots = snapshots
    }

    public func snapshot(for provider: AIProvider) -> UsageSnapshot? {
        snapshots.first { $0.provider == provider }
    }
}

public enum SnapshotCoding {
    public static func encode(_ envelope: SnapshotEnvelope) throws -> Data {
        try JSONEncoder().encode(envelope)
    }

    public static func decode(_ data: Data) throws -> SnapshotEnvelope {
        let envelope = try JSONDecoder().decode(SnapshotEnvelope.self, from: data)
        guard envelope.version == SnapshotEnvelope.currentVersion else {
            throw UsageProviderError.schemaChanged
        }
        return envelope
    }
}
