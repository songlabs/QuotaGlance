import Foundation
import QuotaGlanceCore
import WatchConnectivity

@MainActor
final class WatchConnectivityReceiver: NSObject, WCSessionDelegate {
    private var receive: ((SnapshotEnvelope) -> Void)?
    private let session: WCSession?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
    }

    func start(receive: @escaping (SnapshotEnvelope) -> Void) {
        self.receive = receive
        session?.delegate = self
        session?.activate()
        if let data = session?.receivedApplicationContext["snapshotEnvelope"] as? Data,
           let envelope = try? SnapshotCoding.decode(data) {
            receive(envelope)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["snapshotEnvelope"] as? Data,
              let envelope = try? SnapshotCoding.decode(data)
        else { return }
        Task { @MainActor [weak self] in self?.receive?(envelope) }
    }
}
