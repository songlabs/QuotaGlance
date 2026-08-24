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
    public let accountIdentifier: UUID?
    public let session: UsageWindow?
    public let weekly: UsageWindow?
    public let updatedAt: Date

    public init(
        provider: AIProvider,
        accountIdentifier: UUID? = nil,
        session: UsageWindow?,
        weekly: UsageWindow?,
        updatedAt: Date
    ) {
        self.provider = provider
        self.accountIdentifier = accountIdentifier
        self.session = session
        self.weekly = weekly
        self.updatedAt = updatedAt
    }

    public var id: String {
        accountIdentifier.map { "\(provider.rawValue).\($0.uuidString)" } ?? provider.rawValue
    }

    public func assigned(to accountIdentifier: UUID) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            accountIdentifier: accountIdentifier,
            session: session,
            weekly: weekly,
            updatedAt: updatedAt
        )
    }
}

public struct ProviderAccount: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let provider: AIProvider
    public let ordinal: Int
    public let identityLabel: String?
    public let customDisplayName: String?

    public init(
        id: UUID,
        provider: AIProvider,
        ordinal: Int,
        identityLabel: String? = nil,
        customDisplayName: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.ordinal = ordinal
        self.identityLabel = identityLabel
        self.customDisplayName = customDisplayName
    }

    public func replacingIdentityLabel(_ identityLabel: String?) -> ProviderAccount {
        ProviderAccount(
            id: id,
            provider: provider,
            ordinal: ordinal,
            identityLabel: identityLabel ?? self.identityLabel,
            customDisplayName: customDisplayName
        )
    }

    public func replacingCustomDisplayName(_ customDisplayName: String) -> ProviderAccount {
        let trimmedName = customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProviderAccount(
            id: id,
            provider: provider,
            ordinal: ordinal,
            identityLabel: identityLabel,
            customDisplayName: trimmedName.isEmpty ? nil : trimmedName
        )
    }

    public func displayName(fallback: String) -> String {
        customDisplayName ?? identityLabel ?? fallback
    }
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

    public func snapshot(for provider: AIProvider, accountIdentifier: UUID?) -> UsageSnapshot? {
        if let accountIdentifier,
           let exact = snapshots.first(where: {
               $0.provider == provider && $0.accountIdentifier == accountIdentifier
           }) {
            return exact
        }
        return snapshot(for: provider)
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
