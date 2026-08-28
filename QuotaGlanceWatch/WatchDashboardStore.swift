import Observation
import QuotaGlanceCore
import WidgetKit

@Observable
@MainActor
final class WatchDashboardStore {
    private static let complicationKind = "QuotaGlanceComplication"
    private let cache: WatchSnapshotStore
    private var receiver: WatchConnectivityReceiver!
    var envelope: SnapshotEnvelope?
    var isRefreshing = false
    var refreshFailed = false

    init(cache: WatchSnapshotStore = WatchSnapshotStore()) {
        self.cache = cache
        envelope = cache.load()
        if envelope != nil {
            WidgetCenter.shared.reloadTimelines(ofKind: Self.complicationKind)
        }
        receiver = WatchConnectivityReceiver()
        receiver.start { [weak self] envelope in
            self?.apply(envelope)
        }
    }

    func apply(_ envelope: SnapshotEnvelope) {
        let saved = cache.save(envelope)
        self.envelope = envelope
        refreshFailed = false
        if saved {
            WidgetCenter.shared.reloadTimelines(ofKind: Self.complicationKind)
        }
    }

    var latestUpdatedAt: Date? {
        envelope?.watchAccountPresentations.compactMap { $0.snapshot?.updatedAt }.max()
    }

    func accountPresentations(for provider: AIProvider) -> [AccountUsagePresentation] {
        envelope?.watchAccountPresentations
            .filter { $0.provider == provider }
            .sorted { $0.ordinal < $1.ordinal } ?? []
    }

    var hasProFeatures: Bool { envelope?.hasProFeatures() ?? false }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshFailed = false
        defer { isRefreshing = false }

        do {
            let response = try await receiver.requestRefresh()
            if let envelope = response.envelope {
                apply(envelope)
            }
            if !response.succeeded {
                refreshFailed = true
            }
        } catch {
            refreshFailed = true
        }
    }
}
