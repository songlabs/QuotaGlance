import Foundation
import QuotaGlanceCore

@MainActor
protocol SnapshotCaching: AnyObject {
    func load() -> SnapshotEnvelope?
    func save(_ envelope: SnapshotEnvelope) throws
    func prepareAppReviewDemoSnapshot() throws -> SnapshotEnvelope?
    func restoreProductionSnapshotAfterAppReviewDemo() throws -> SnapshotEnvelope
    func recoverInterruptedAppReviewDemoSnapshot() -> (envelope: SnapshotEnvelope?, didRecover: Bool)
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
    static let appReviewDemoProductionSnapshotKey = "appReviewDemo.productionSnapshot.v1"
    static let appReviewDemoBackupActiveKey = "appReviewDemo.productionSnapshotBackupActive.v1"

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

    func prepareAppReviewDemoSnapshot() throws -> SnapshotEnvelope? {
        guard let defaults else { throw AppReviewDemoSnapshotCacheError.unavailable }
        let productionEnvelope = load()
        guard productionEnvelope?.isAppReviewDemo != true else {
            throw AppReviewDemoSnapshotCacheError.invalidProductionSnapshot
        }

        if let productionEnvelope {
            defaults.set(
                try SnapshotCoding.encode(productionEnvelope),
                forKey: Self.appReviewDemoProductionSnapshotKey
            )
        } else {
            defaults.removeObject(forKey: Self.appReviewDemoProductionSnapshotKey)
        }
        defaults.set(true, forKey: Self.appReviewDemoBackupActiveKey)

        guard defaults.bool(forKey: Self.appReviewDemoBackupActiveKey) else {
            clearAppReviewDemoBackup()
            throw AppReviewDemoSnapshotCacheError.verificationFailed
        }
        if let productionEnvelope {
            guard let storedData = defaults.data(forKey: Self.appReviewDemoProductionSnapshotKey),
                  try SnapshotCoding.decode(storedData) == productionEnvelope
            else {
                clearAppReviewDemoBackup()
                throw AppReviewDemoSnapshotCacheError.verificationFailed
            }
        } else if defaults.data(forKey: Self.appReviewDemoProductionSnapshotKey) != nil {
            clearAppReviewDemoBackup()
            throw AppReviewDemoSnapshotCacheError.verificationFailed
        }
        return productionEnvelope
    }

    func restoreProductionSnapshotAfterAppReviewDemo() throws -> SnapshotEnvelope {
        guard let defaults else { throw AppReviewDemoSnapshotCacheError.unavailable }

        let productionEnvelope: SnapshotEnvelope
        if defaults.bool(forKey: Self.appReviewDemoBackupActiveKey) {
            if let data = defaults.data(forKey: Self.appReviewDemoProductionSnapshotKey) {
                productionEnvelope = try SnapshotCoding.decode(data)
                guard !productionEnvelope.isAppReviewDemo else {
                    throw AppReviewDemoSnapshotCacheError.invalidProductionSnapshot
                }
            } else {
                productionEnvelope = SnapshotEnvelope(snapshots: [])
            }
        } else if let current = load(), !current.isAppReviewDemo {
            productionEnvelope = current
        } else {
            productionEnvelope = SnapshotEnvelope(snapshots: [])
        }

        try save(productionEnvelope)
        guard load() == productionEnvelope else {
            throw AppReviewDemoSnapshotCacheError.verificationFailed
        }
        clearAppReviewDemoBackup()
        return productionEnvelope
    }

    func recoverInterruptedAppReviewDemoSnapshot() -> (envelope: SnapshotEnvelope?, didRecover: Bool) {
        let currentEnvelope = load()
        guard currentEnvelope?.isAppReviewDemo == true else {
            clearAppReviewDemoBackup()
            return (currentEnvelope, false)
        }

        do {
            return (try restoreProductionSnapshotAfterAppReviewDemo(), true)
        } catch {
            // Never allow a Release relaunch to remain in App Review Demo Mode.
            let emptyProductionEnvelope = SnapshotEnvelope(snapshots: [])
            try? save(emptyProductionEnvelope)
            clearAppReviewDemoBackup()
            return (load() ?? emptyProductionEnvelope, true)
        }
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

    private func clearAppReviewDemoBackup() {
        defaults?.removeObject(forKey: Self.appReviewDemoProductionSnapshotKey)
        defaults?.removeObject(forKey: Self.appReviewDemoBackupActiveKey)
    }
}

private enum AppReviewDemoSnapshotCacheError: Error {
    case unavailable
    case invalidProductionSnapshot
    case verificationFailed
}
