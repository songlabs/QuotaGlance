import Foundation
import QuotaGlanceCore
import WatchConnectivity

@MainActor
protocol PhoneWatchSynchronizing: AnyObject {
    func send(_ envelope: SnapshotEnvelope)
    func setRefreshHandler(_ handler: @escaping @MainActor () async -> Bool)
}

@MainActor
final class PhoneWatchSync: NSObject, PhoneWatchSynchronizing, WCSessionDelegate {
    private let session: WCSession?
    private var pendingData: Data?
    private var latestData: Data?
    private var refreshHandler: (@MainActor () async -> Bool)?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func send(_ envelope: SnapshotEnvelope) {
        guard let data = try? SnapshotCoding.encode(envelope) else { return }
        pendingData = data
        latestData = data
        flush()
    }

    func setRefreshHandler(_ handler: @escaping @MainActor () async -> Bool) {
        refreshHandler = handler
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in self?.flush() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message[WatchSyncMessageKey.refreshUsage] as? Bool == true else {
            replyHandler([WatchSyncMessageKey.refreshSucceeded: false])
            return
        }
        Task { @MainActor [weak self] in
            guard let self, let refreshHandler = self.refreshHandler else {
                replyHandler([WatchSyncMessageKey.refreshSucceeded: false])
                return
            }
            let succeeded = await refreshHandler()
            var reply: [String: Any] = [WatchSyncMessageKey.refreshSucceeded: succeeded]
            if let latestData = self.latestData {
                reply[WatchSyncMessageKey.snapshotEnvelope] = latestData
            }
            replyHandler(reply)
        }
    }

    private func flush() {
        guard session?.activationState == .activated, let pendingData else { return }
        do {
            try session?.updateApplicationContext([WatchSyncMessageKey.snapshotEnvelope: pendingData])
            self.pendingData = nil
        } catch {
            // Keep the latest non-sensitive snapshot queued for the next activation or refresh.
        }
    }
}
