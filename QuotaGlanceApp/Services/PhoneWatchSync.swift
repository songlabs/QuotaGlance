import Foundation
import QuotaGlanceCore
import WatchConnectivity

@MainActor
protocol PhoneWatchSynchronizing: AnyObject {
    func send(_ envelope: SnapshotEnvelope)
}

@MainActor
final class PhoneWatchSync: NSObject, PhoneWatchSynchronizing, WCSessionDelegate {
    private let session: WCSession?
    private var pendingData: Data?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func send(_ envelope: SnapshotEnvelope) {
        guard let data = try? SnapshotCoding.encode(envelope) else { return }
        pendingData = data
        flush()
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

    private func flush() {
        guard session?.activationState == .activated, let pendingData else { return }
        do {
            try session?.updateApplicationContext(["snapshotEnvelope": pendingData])
            self.pendingData = nil
        } catch {
            // Keep the latest non-sensitive snapshot queued for the next activation or refresh.
        }
    }
}
