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

public enum QuotaDisplayLimit: String, Codable, CaseIterable, Equatable, Sendable {
    case fiveHour
    case weekly

    public func window(in snapshot: UsageSnapshot) -> UsageWindow? {
        switch self {
        case .fiveHour: snapshot.session
        case .weekly: snapshot.weekly
        }
    }
}

public enum AccessLevel: String, Codable, Equatable, Sendable {
    case trial
    case free
    case pro

    public var hasProFeatures: Bool { self != .free }

    public static func resolve(
        hasLifetimePurchase: Bool,
        trialPurchaseDate: Date?,
        trialDuration: TimeInterval,
        now: Date
    ) -> Self {
        if hasLifetimePurchase { return .pro }
        guard let trialPurchaseDate else { return .free }
        return now < trialPurchaseDate.addingTimeInterval(trialDuration) ? .trial : .free
    }
}

public enum EntitlementPublicationPolicy {
    public static func canPublish(isEntitlementLoaded: Bool) -> Bool {
        isEntitlementLoaded
    }
}

public enum RefreshIntervalUnit: String, CaseIterable, Equatable, Identifiable, Sendable {
    case minute
    case hour

    public var id: String { rawValue }

    public var valueRange: ClosedRange<Int> {
        switch self {
        case .minute: 0...60
        case .hour: 0...23
        }
    }

    fileprivate var secondsPerUnit: TimeInterval {
        switch self {
        case .minute: 60
        case .hour: 60 * 60
        }
    }

    fileprivate func clamped(_ value: Int) -> Int {
        min(max(value, valueRange.lowerBound), valueRange.upperBound)
    }
}

public struct RefreshInterval: Equatable, Sendable {
    public static let fixedFreeInterval = RefreshInterval(value: 60, unit: .minute)
    public static let defaultInterval = RefreshInterval(value: 60, unit: .minute)

    public let value: Int
    public let unit: RefreshIntervalUnit

    public init(value: Int, unit: RefreshIntervalUnit) {
        self.value = unit.clamped(value)
        self.unit = unit
    }

    fileprivate init(persistedValue: Int, unit: RefreshIntervalUnit) {
        value = persistedValue
        self.unit = unit
    }

    public var timeInterval: TimeInterval? {
        value == 0 ? nil : TimeInterval(value) * unit.secondsPerUnit
    }

    public func replacingValue(_ value: Int) -> RefreshInterval {
        RefreshInterval(value: value, unit: unit)
    }

    public func replacingUnit(_ unit: RefreshIntervalUnit) -> RefreshInterval {
        RefreshInterval(value: value, unit: unit)
    }

    public func effective(for accessLevel: AccessLevel) -> RefreshInterval {
        accessLevel.hasProFeatures ? self : Self.fixedFreeInterval
    }

    public func shouldRefresh(
        lastSuccessfulUpdate: Date?,
        force: Bool = false,
        now: Date = Date()
    ) -> Bool {
        if force { return true }
        guard let timeInterval else { return false }
        guard let lastSuccessfulUpdate else { return true }
        return now.timeIntervalSince(lastSuccessfulUpdate) >= timeInterval
    }
}

public enum RefreshIntervalPreferences {
    public static let valueKey = "refreshInterval.value"
    public static let unitKey = "refreshInterval.unit"

    public static func load(from defaults: UserDefaults) -> RefreshInterval {
        let fallback = RefreshInterval.defaultInterval
        guard let unitValue = defaults.string(forKey: unitKey),
              let unit = RefreshIntervalUnit(rawValue: unitValue),
              defaults.object(forKey: valueKey) != nil
        else { return fallback }
        let value = defaults.integer(forKey: valueKey)
        if unit == .minute, value > unit.valueRange.upperBound {
            return RefreshInterval(persistedValue: value, unit: unit)
        }
        return RefreshInterval(value: value, unit: unit)
    }

    public static func save(_ interval: RefreshInterval, to defaults: UserDefaults) {
        defaults.set(interval.value, forKey: valueKey)
        defaults.set(interval.unit.rawValue, forKey: unitKey)
    }
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
        if let customDisplayName {
            return customDisplayName
        }
        guard let identityLabel else { return fallback }
        let trimmedIdentity = identityLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmedIdentity.firstIndex(of: "@"), atIndex != trimmedIdentity.startIndex else {
            return trimmedIdentity.isEmpty ? fallback : trimmedIdentity
        }
        return String(trimmedIdentity[..<atIndex])
    }
}

public struct AccountDisplayMetadata: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let provider: AIProvider
    public let ordinal: Int
    public let displayName: String

    public init(id: UUID, provider: AIProvider, ordinal: Int, displayName: String) {
        self.id = id
        self.provider = provider
        self.ordinal = ordinal
        self.displayName = displayName
    }
}

public struct AccountUsagePresentation: Equatable, Identifiable, Sendable {
    public let id: String
    public let accountIdentifier: UUID?
    public let provider: AIProvider
    public let ordinal: Int
    public let displayName: String
    public let snapshot: UsageSnapshot?

    public init(
        id: String,
        accountIdentifier: UUID?,
        provider: AIProvider,
        ordinal: Int,
        displayName: String,
        snapshot: UsageSnapshot?
    ) {
        self.id = id
        self.accountIdentifier = accountIdentifier
        self.provider = provider
        self.ordinal = ordinal
        self.displayName = displayName
        self.snapshot = snapshot
    }
}

public enum WatchAccountSelection {
    public static let maximumCount = 2

    public static func normalized(_ identifiers: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return identifiers.filter { seen.insert($0).inserted }.prefix(maximumCount).map { $0 }
    }

    public static func adding(_ identifier: UUID, to identifiers: [UUID]) -> [UUID]? {
        let current = normalized(identifiers)
        if current.contains(identifier) { return current }
        guard current.count < maximumCount else { return nil }
        return current + [identifier]
    }
}

public enum WatchSyncMessageKey {
    public static let snapshotEnvelope = "snapshotEnvelope"
    public static let refreshUsage = "refreshUsage"
    public static let refreshSucceeded = "refreshSucceeded"
}

public enum SettingsUpgradeRouting {
    public static func shouldPresentMembership(for accessLevel: AccessLevel) -> Bool {
        accessLevel != .pro
    }
}

public enum WatchRefreshScope {
    public static func accountIdentifiers(
        accounts: [UUID],
        selectedAccountIdentifiers: [UUID],
        hasProFeatures: Bool
    ) -> Set<UUID> {
        Set(hasProFeatures ? selectedAccountIdentifiers : Array(accounts.prefix(1)))
    }
}

public struct SnapshotEnvelope: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let snapshots: [UsageSnapshot]
    public let displayLimit: QuotaDisplayLimit
    public let accounts: [AccountDisplayMetadata]
    public let watchAccountIdentifiers: [UUID]
    public let accessLevel: AccessLevel
    public let proAccessExpiresAt: Date?

    public init(
        version: Int = Self.currentVersion,
        snapshots: [UsageSnapshot],
        displayLimit: QuotaDisplayLimit = .fiveHour,
        accounts: [AccountDisplayMetadata] = [],
        watchAccountIdentifiers: [UUID] = [],
        accessLevel: AccessLevel = .free,
        proAccessExpiresAt: Date? = nil
    ) {
        self.version = version
        self.snapshots = snapshots
        self.displayLimit = displayLimit
        self.accounts = accounts
        self.watchAccountIdentifiers = WatchAccountSelection.normalized(watchAccountIdentifiers)
        self.accessLevel = accessLevel
        self.proAccessExpiresAt = proAccessExpiresAt
    }

    public func hasProFeatures(at date: Date = Date()) -> Bool {
        switch accessLevel {
        case .free: false
        case .pro: true
        case .trial: proAccessExpiresAt.map { date < $0 } ?? false
        }
    }

    public func timelineEntryDates(from date: Date) -> [Date] {
        guard accessLevel == .trial,
              let proAccessExpiresAt,
              proAccessExpiresAt > date else { return [date] }
        return [date, proAccessExpiresAt]
    }

    public func removingAccount(_ accountIdentifier: UUID) -> SnapshotEnvelope {
        SnapshotEnvelope(
            version: version,
            snapshots: snapshots.filter { $0.accountIdentifier != accountIdentifier },
            displayLimit: displayLimit,
            accounts: accounts.filter { $0.id != accountIdentifier },
            watchAccountIdentifiers: watchAccountIdentifiers.filter { $0 != accountIdentifier },
            accessLevel: accessLevel,
            proAccessExpiresAt: proAccessExpiresAt
        )
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

    public var accountPresentations: [AccountUsagePresentation] {
        if !accounts.isEmpty {
            return accounts.map { account in
                AccountUsagePresentation(
                    id: account.id.uuidString,
                    accountIdentifier: account.id,
                    provider: account.provider,
                    ordinal: account.ordinal,
                    displayName: account.displayName,
                    snapshot: snapshots.first {
                        $0.provider == account.provider && $0.accountIdentifier == account.id
                    }
                )
            }
        }

        return snapshots.enumerated().map { index, snapshot in
            AccountUsagePresentation(
                id: "legacy.\(index).\(snapshot.id)",
                accountIdentifier: snapshot.accountIdentifier,
                provider: snapshot.provider,
                ordinal: index + 1,
                displayName: snapshot.provider.displayName,
                snapshot: snapshot
            )
        }
    }

    public var watchAccountPresentations: [AccountUsagePresentation] {
        watchAccountPresentations(at: Date())
    }

    public func watchAccountPresentations(at date: Date) -> [AccountUsagePresentation] {
        let presentations = accountPresentations
        guard hasProFeatures(at: date) else { return Array(presentations.prefix(1)) }
        guard !watchAccountIdentifiers.isEmpty else {
            return accounts.isEmpty
                ? Array(presentations.prefix(WatchAccountSelection.maximumCount))
                : []
        }
        return watchAccountIdentifiers.compactMap { identifier in
            presentations.first { $0.accountIdentifier == identifier }
        }
    }

    public func effectiveDisplayLimit(at date: Date = Date()) -> QuotaDisplayLimit {
        hasProFeatures(at: date) ? displayLimit : .fiveHour
    }

    enum CodingKeys: String, CodingKey {
        case version
        case snapshots
        case displayLimit
        case accounts
        case watchAccountIdentifiers
        case accessLevel
        case proAccessExpiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        snapshots = try container.decode([UsageSnapshot].self, forKey: .snapshots)
        displayLimit = try container.decodeIfPresent(QuotaDisplayLimit.self, forKey: .displayLimit) ?? .fiveHour
        accounts = try container.decodeIfPresent([AccountDisplayMetadata].self, forKey: .accounts) ?? []
        accessLevel = try container.decodeIfPresent(AccessLevel.self, forKey: .accessLevel) ?? .free
        proAccessExpiresAt = try container.decodeIfPresent(Date.self, forKey: .proAccessExpiresAt)
        if let identifiers = try container.decodeIfPresent([UUID].self, forKey: .watchAccountIdentifiers) {
            watchAccountIdentifiers = WatchAccountSelection.normalized(identifiers)
        } else {
            let legacyIdentifiers = accounts.isEmpty
                ? snapshots.compactMap(\.accountIdentifier)
                : accounts.map(\.id)
            watchAccountIdentifiers = WatchAccountSelection.normalized(legacyIdentifiers)
        }
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

/// Shared persistence contract for the watch app and its complication.
public struct SharedWatchSnapshotCache {
    public static let suiteName = "group.com.songlabs.QuotaGlance.watch"
    public static let key = "usageSnapshotEnvelope"

    private let defaults: UserDefaults?

    public init(suiteName: String = Self.suiteName) {
        defaults = UserDefaults(suiteName: suiteName)
    }

    public var isAvailable: Bool { defaults != nil }

    @discardableResult
    public func save(_ envelope: SnapshotEnvelope) -> Bool {
        guard let defaults, let data = try? SnapshotCoding.encode(envelope) else { return false }
        defaults.set(data, forKey: Self.key)
        guard let storedData = defaults.data(forKey: Self.key) else { return false }
        return (try? SnapshotCoding.decode(storedData)) == envelope
    }

    public func load() -> SnapshotEnvelope? {
        guard let data = defaults?.data(forKey: Self.key) else { return nil }
        return try? SnapshotCoding.decode(data)
    }
}
