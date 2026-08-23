import Foundation
import QuotaGlanceCore

@MainActor
protocol SnapshotCaching: AnyObject {
    func load() -> SnapshotEnvelope?
    func save(_ envelope: SnapshotEnvelope) throws
    func remove(_ provider: AIProvider) throws
}
@MainActor
final class AppGroupSnapshotCache: SnapshotCaching {
    static let suiteName = "group.com.songlabs.QuotaGlance"
    static let snapshotsKey = "usageSnapshotEnvelope"
    static let defaultProviderKey = "defaultProvider"

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

    func remove(_ provider: AIProvider) throws {
        let remaining = load()?.snapshots.filter { $0.provider != provider } ?? []
        try save(SnapshotEnvelope(snapshots: remaining))
    }

    var defaultProvider: AIProvider {
        get {
            defaults?.string(forKey: Self.defaultProviderKey).flatMap(AIProvider.init(rawValue:)) ?? .codex
        }
        set {
            defaults?.set(newValue.rawValue, forKey: Self.defaultProviderKey)
        }
    }
}
