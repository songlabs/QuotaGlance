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

    public func effective(for accessLevel: AccessLevel) -> Self {
        accessLevel.hasProFeatures ? self : .fiveHour
    }

    public func window(in snapshot: UsageSnapshot) -> UsageWindow? {
        switch self {
        case .fiveHour: snapshot.session
        case .weekly: snapshot.weekly
        }
    }
}

public enum AccessLevel: String, Codable, Equatable, Hashable, Sendable {
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

public enum AutomaticRefreshInterval: String, CaseIterable, Equatable, Identifiable, Sendable {
    case disabled
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours

    public static let fixedFreeInterval: Self = .fourHours
    public static let defaultInterval: Self = .fourHours

    public var id: String { rawValue }

    public var timeInterval: TimeInterval? {
        switch self {
        case .disabled: nil
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .twoHours: 2 * 60 * 60
        case .fourHours: 4 * 60 * 60
        }
    }

    public func effective(for accessLevel: AccessLevel) -> Self {
        accessLevel.hasProFeatures ? self : Self.fixedFreeInterval
    }

    public func shouldRefresh(
        lastSuccessfulUpdate: Date?,
        lastRefreshAttempt: Date? = nil,
        force: Bool = false,
        now: Date = Date()
    ) -> Bool {
        if force { return true }
        guard let timeInterval else { return false }
        guard let referenceDate = [lastSuccessfulUpdate, lastRefreshAttempt].compactMap({ $0 }).max()
        else { return true }
        return now.timeIntervalSince(referenceDate) >= timeInterval
    }

    public func nextRefreshDate(
        lastSuccessfulUpdate: Date?,
        lastRefreshAttempt: Date? = nil,
        now: Date = Date()
    ) -> Date? {
        guard let timeInterval else { return nil }
        guard let referenceDate = [lastSuccessfulUpdate, lastRefreshAttempt].compactMap({ $0 }).max()
        else { return now }
        return max(now, referenceDate.addingTimeInterval(timeInterval))
    }

    public func earliestBackgroundBeginDate(from date: Date = Date()) -> Date? {
        timeInterval.map(date.addingTimeInterval)
    }

    public static func migratingLegacy(value: Int, unit: String) -> Self? {
        switch unit {
        case "minute":
            switch value {
            case ...0: .disabled
            case 1...15: .fifteenMinutes
            case 16...30: .thirtyMinutes
            case 31...60: .oneHour
            case 61...120: .twoHours
            default: .fourHours
            }
        case "hour":
            switch value {
            case ...0: .disabled
            case 1: .oneHour
            case 2: .twoHours
            default: .fourHours
            }
        default:
            nil
        }
    }
}

public struct CodexResetCredit: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let resetType: String?
    public let status: String
    public let title: String?
    public let expiresAt: Date?

    public init(
        id: String,
        resetType: String? = nil,
        status: String,
        title: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.resetType = resetType
        self.status = status
        self.title = title
        self.expiresAt = expiresAt
    }

    public var isAvailable: Bool {
        status.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("available") == .orderedSame
    }

    public var providerTitle: String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case id
        case resetType = "reset_type"
        case status
        case title
        case expiresAt = "expires_at"
    }
}

public struct CodexResetCreditDetails: Decodable, Equatable, Sendable {
    public let credits: [CodexResetCredit]

    public init(credits: [CodexResetCredit]) {
        self.credits = credits
    }
}

public enum ResetCreditPresentationPolicy {
    public static func showsRow(provider: AIProvider, availableCount: Int?) -> Bool {
        provider == .codex && availableCount != nil
    }

    public static func allowsExpansion(provider: AIProvider, availableCount: Int?) -> Bool {
        provider == .codex && (availableCount ?? 0) > 0
    }

    public static func sortedAvailableCredits(
        in details: CodexResetCreditDetails
    ) -> [CodexResetCredit] {
        details.credits
            .filter(\.isAvailable)
            .sorted { lhs, rhs in
                switch (lhs.expiresAt, rhs.expiresAt) {
                case (let lhsDate?, let rhsDate?) where lhsDate != rhsDate:
                    lhsDate < rhsDate
                case (_?, nil):
                    true
                case (nil, _?):
                    false
                default:
                    lhs.id < rhs.id
                }
            }
    }

    public static func nearestExpiration(in details: CodexResetCreditDetails) -> Date? {
        sortedAvailableCredits(in: details).compactMap(\.expiresAt).first
    }
}

public enum AutomaticRefreshPreferences {
    public static let intervalKey = "automaticRefreshInterval.v2"
    public static let legacyValueKey = "refreshInterval.value"
    public static let legacyUnitKey = "refreshInterval.unit"

    public static func load(from defaults: UserDefaults) -> AutomaticRefreshInterval {
        if let value = defaults.string(forKey: intervalKey),
           let interval = AutomaticRefreshInterval(rawValue: value) {
            return interval
        }

        let interval: AutomaticRefreshInterval
        if defaults.object(forKey: legacyValueKey) != nil,
           let unit = defaults.string(forKey: legacyUnitKey),
           let migrated = AutomaticRefreshInterval.migratingLegacy(
               value: defaults.integer(forKey: legacyValueKey),
               unit: unit
           ) {
            interval = migrated
        } else {
            interval = .defaultInterval
        }
        save(interval, to: defaults)
        return interval
    }

    public static func save(_ interval: AutomaticRefreshInterval, to defaults: UserDefaults) {
        defaults.set(interval.rawValue, forKey: intervalKey)
    }
}

public struct UsageSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let provider: AIProvider
    public let accountIdentifier: UUID?
    public let session: UsageWindow?
    public let weekly: UsageWindow?
    public let availableResetCount: Int?
    public let updatedAt: Date

    public init(
        provider: AIProvider,
        accountIdentifier: UUID? = nil,
        session: UsageWindow?,
        weekly: UsageWindow?,
        availableResetCount: Int? = nil,
        updatedAt: Date
    ) {
        self.provider = provider
        self.accountIdentifier = accountIdentifier
        self.session = session
        self.weekly = weekly
        self.availableResetCount = availableResetCount
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
            availableResetCount: availableResetCount,
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

    public static func removing(_ identifier: UUID, from identifiers: [UUID]) -> [UUID] {
        normalized(identifiers).filter { $0 != identifier }
    }

    public static func position(of identifier: UUID, in identifiers: [UUID]) -> Int? {
        normalized(identifiers).firstIndex(of: identifier).map { $0 + 1 }
    }

    public static func initial(
        accountIdentifiers: [UUID],
        legacySelectedAccountIdentifiers: [UUID]
    ) -> [UUID] {
        normalized(
            legacySelectedAccountIdentifiers.isEmpty
                ? Array(accountIdentifiers.prefix(1))
                : legacySelectedAccountIdentifiers
        )
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
    public let isAppReviewDemo: Bool
    public let appReviewDemoDefaultProvider: AIProvider?
    public let appReviewDemoSelectedAccountIdentifiers: [AIProvider: UUID]

    public init(
        version: Int = Self.currentVersion,
        snapshots: [UsageSnapshot],
        displayLimit: QuotaDisplayLimit = .fiveHour,
        accounts: [AccountDisplayMetadata] = [],
        watchAccountIdentifiers: [UUID] = [],
        accessLevel: AccessLevel = .free,
        proAccessExpiresAt: Date? = nil,
        isAppReviewDemo: Bool = false,
        appReviewDemoDefaultProvider: AIProvider? = nil,
        appReviewDemoSelectedAccountIdentifiers: [AIProvider: UUID] = [:]
    ) {
        self.version = version
        self.snapshots = snapshots
        self.displayLimit = displayLimit
        self.accounts = accounts
        self.watchAccountIdentifiers = WatchAccountSelection.normalized(watchAccountIdentifiers)
        self.accessLevel = accessLevel
        self.proAccessExpiresAt = proAccessExpiresAt
        self.isAppReviewDemo = isAppReviewDemo
        self.appReviewDemoDefaultProvider = appReviewDemoDefaultProvider
        self.appReviewDemoSelectedAccountIdentifiers = appReviewDemoSelectedAccountIdentifiers
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
            proAccessExpiresAt: proAccessExpiresAt,
            isAppReviewDemo: isAppReviewDemo,
            appReviewDemoDefaultProvider: appReviewDemoDefaultProvider,
            appReviewDemoSelectedAccountIdentifiers: appReviewDemoSelectedAccountIdentifiers.filter {
                $0.value != accountIdentifier
            }
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
        case isAppReviewDemo
        case appReviewDemoDefaultProvider
        case appReviewDemoSelectedAccountIdentifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        snapshots = try container.decode([UsageSnapshot].self, forKey: .snapshots)
        displayLimit = try container.decodeIfPresent(QuotaDisplayLimit.self, forKey: .displayLimit) ?? .fiveHour
        accounts = try container.decodeIfPresent([AccountDisplayMetadata].self, forKey: .accounts) ?? []
        accessLevel = try container.decodeIfPresent(AccessLevel.self, forKey: .accessLevel) ?? .free
        proAccessExpiresAt = try container.decodeIfPresent(Date.self, forKey: .proAccessExpiresAt)
        isAppReviewDemo = try container.decodeIfPresent(Bool.self, forKey: .isAppReviewDemo) ?? false
        appReviewDemoDefaultProvider = try container.decodeIfPresent(
            AIProvider.self,
            forKey: .appReviewDemoDefaultProvider
        )
        appReviewDemoSelectedAccountIdentifiers = try container.decodeIfPresent(
            [AIProvider: UUID].self,
            forKey: .appReviewDemoSelectedAccountIdentifiers
        ) ?? [:]
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

public enum AppReviewDemoWidgetPolicy {
    public static func defaultProvider(in envelope: SnapshotEnvelope) -> AIProvider {
        if let requested = envelope.appReviewDemoDefaultProvider,
           envelope.accounts.contains(where: { $0.provider == requested }) {
            return requested
        }
        return envelope.accounts.first?.provider
            ?? envelope.snapshots.first?.provider
            ?? .codex
    }

    public static func selectedAccountIdentifier(
        for provider: AIProvider,
        in envelope: SnapshotEnvelope
    ) -> UUID? {
        if let requested = envelope.appReviewDemoSelectedAccountIdentifiers[provider],
           envelope.accounts.contains(where: { $0.id == requested && $0.provider == provider }) {
            return requested
        }
        return envelope.accounts.first { $0.provider == provider }?.id
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
