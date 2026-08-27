import Foundation
import QuotaGlanceCore

@MainActor
protocol SnapshotCaching: AnyObject {
    func load() -> SnapshotEnvelope?
    func save(_ envelope: SnapshotEnvelope) throws
    func remove(accountIdentifier: UUID) throws
    func selectedAccountIdentifier(for provider: AIProvider) -> UUID?
    func setSelectedAccountIdentifier(_ accountIdentifier: UUID?, for provider: AIProvider)
    func watchAccountIdentifiers() -> [UUID]?
    func setWatchAccountIdentifiers(_ accountIdentifiers: [UUID])
}
@MainActor
final class AppGroupSnapshotCache: SnapshotCaching {
    static let suiteName = "group.com.songlabs.QuotaGlance"
    static let snapshotsKey = "usageSnapshotEnvelope"
    static let defaultProviderKey = "defaultProvider"
    static let displayLimitKey = "displayLimit"
    static let selectedAccountKeyPrefix = "selectedAccount."
    static let watchAccountIdentifiersKey = "watchSelectedAccounts.v1"

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: suiteName)) {
        self.defaults = defaults
    }

    func load() -> SnapshotEnvelope? {
        guard let data = defaults?.data(forKey: Self.snapshotsKey) else { return nil }
        return try? SnapshotCoding.decode(data)
    }

    func save(_ envelope: SnapshotEnvelope) throws {
        defaults?.set(try SnapshotCoding.encode(envelope), forKey: Self.snapshotsKey)
    }

    func remove(accountIdentifier: UUID) throws {
        try save(load()?.removingAccount(accountIdentifier) ?? SnapshotEnvelope(snapshots: []))
    }

    func selectedAccountIdentifier(for provider: AIProvider) -> UUID? {
        defaults?.string(forKey: selectedAccountKey(for: provider)).flatMap(UUID.init(uuidString:))
    }

    func setSelectedAccountIdentifier(_ accountIdentifier: UUID?, for provider: AIProvider) {
        let key = selectedAccountKey(for: provider)
        if let accountIdentifier {
            defaults?.set(accountIdentifier.uuidString, forKey: key)
        } else {
            defaults?.removeObject(forKey: key)
        }
    }

    func watchAccountIdentifiers() -> [UUID]? {
        guard let values = defaults?.array(forKey: Self.watchAccountIdentifiersKey) as? [String] else {
            return nil
        }
        return WatchAccountSelection.normalized(values.compactMap(UUID.init(uuidString:)))
    }

    func setWatchAccountIdentifiers(_ accountIdentifiers: [UUID]) {
        let values = WatchAccountSelection.normalized(accountIdentifiers).map(\.uuidString)
        defaults?.set(values, forKey: Self.watchAccountIdentifiersKey)
    }

    var defaultProvider: AIProvider {
        get {
            defaults?.string(forKey: Self.defaultProviderKey).flatMap(AIProvider.init(rawValue:)) ?? .codex
        }
        set {
            defaults?.set(newValue.rawValue, forKey: Self.defaultProviderKey)
        }
    }

    var displayLimit: QuotaDisplayLimit {
        get {
            defaults?.string(forKey: Self.displayLimitKey).flatMap(QuotaDisplayLimit.init(rawValue:)) ?? .fiveHour
        }
        set {
            defaults?.set(newValue.rawValue, forKey: Self.displayLimitKey)
        }
    }

    private func selectedAccountKey(for provider: AIProvider) -> String {
        Self.selectedAccountKeyPrefix + provider.rawValue
    }
}
