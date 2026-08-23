import Foundation
import QuotaGlanceCore

@MainActor
final class WatchSnapshotStore {
    static let suiteName = "group.com.songlabs.QuotaGlance.watch"
    static let key = "usageSnapshotEnvelope"

    private let defaults = UserDefaults(suiteName: suiteName)

    func load() -> SnapshotEnvelope? {
        guard let data = defaults?.data(forKey: Self.key) else { return nil }
        return try? SnapshotCoding.decode(data)
    }

    func save(_ envelope: SnapshotEnvelope) {
        guard let data = try? SnapshotCoding.encode(envelope) else { return }
        defaults?.set(data, forKey: Self.key)
    }
}
