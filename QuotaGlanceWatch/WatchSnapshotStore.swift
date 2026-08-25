import Foundation
import QuotaGlanceCore

@MainActor
final class WatchSnapshotStore {
    private let cache = SharedWatchSnapshotCache()

    func load() -> SnapshotEnvelope? {
        cache.load()
    }

    func save(_ envelope: SnapshotEnvelope) -> Bool {
        cache.save(envelope)
    }
}
