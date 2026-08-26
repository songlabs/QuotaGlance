import Foundation
import QuotaGlanceCore
import WatchConnectivity

struct WatchRefreshResponse: Sendable {
    let succeeded: Bool
    let envelope: SnapshotEnvelope?
}

private enum WatchConnectivityRequestError: Error {
    case unavailable
}

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
        if let data = session?.receivedApplicationContext[WatchSyncMessageKey.snapshotEnvelope] as? Data,
           let envelope = try? SnapshotCoding.decode(data) {
            receive(envelope)
        }
    }

    func requestRefresh() async throws -> WatchRefreshResponse {
        guard let session,
              session.activationState == .activated,
              session.isReachable
        else {
            throw WatchConnectivityRequestError.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(
                [WatchSyncMessageKey.refreshUsage: true],
                replyHandler: { reply in
                    let envelope = (reply[WatchSyncMessageKey.snapshotEnvelope] as? Data)
                        .flatMap { try? SnapshotCoding.decode($0) }
                    continuation.resume(returning: WatchRefreshResponse(
                        succeeded: reply[WatchSyncMessageKey.refreshSucceeded] as? Bool == true,
                        envelope: envelope
                    ))
                },
                errorHandler: { error in
                    continuation.resume(throwing: error)
                }
            )
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchSyncMessageKey.snapshotEnvelope] as? Data,
              let envelope = try? SnapshotCoding.decode(data)
        else { return }
        Task { @MainActor [weak self] in self?.receive?(envelope) }
    }
}
