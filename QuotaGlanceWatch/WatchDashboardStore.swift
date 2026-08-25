import Observation
import QuotaGlanceCore
import WidgetKit

@Observable
@MainActor
final class WatchDashboardStore {
    private static let complicationKind = "QuotaGlanceComplication"
    private let cache: WatchSnapshotStore
    private var receiver: WatchConnectivityReceiver!
    var snapshots: [AIProvider: UsageSnapshot]

    init(cache: WatchSnapshotStore = WatchSnapshotStore()) {
        self.cache = cache
        let cached = cache.load()?.snapshots ?? []
        snapshots = Dictionary(uniqueKeysWithValues: cached.map { ($0.provider, $0) })
        if !cached.isEmpty {
            WidgetCenter.shared.reloadTimelines(ofKind: Self.complicationKind)
        }
        receiver = WatchConnectivityReceiver()
        receiver.start { [weak self] envelope in
            self?.apply(envelope)
        }
    }

    func apply(_ envelope: SnapshotEnvelope) {
        let saved = cache.save(envelope)
        snapshots = Dictionary(uniqueKeysWithValues: envelope.snapshots.map { ($0.provider, $0) })
        if saved {
            WidgetCenter.shared.reloadTimelines(ofKind: Self.complicationKind)
        }
    }

    var latestUpdatedAt: Date? {
        snapshots.values.map(\.updatedAt).max()
    }
}
