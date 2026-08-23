import AuthenticationServices
import Foundation
import Network
import QuotaGlanceCore
import UIKit

@MainActor
final class LoopbackOAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var webSession: ASWebAuthenticationSession?
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, Error>?
    private var expectedState = ""
    private var authorizationURLBuilder: ((UInt16) -> URL)?

    func authorize(
        expectedState: String,
        preferredPorts: [UInt16] = [],
        makeAuthorizationURL: @escaping (UInt16) -> URL
    ) async throws -> URL {
        guard continuation == nil else {
            throw CancellationError()
        }
        self.expectedState = expectedState
        authorizationURLBuilder = makeAuthorizationURL

        let queue = DispatchQueue(label: "com.songlabs.QuotaGlance.oauth-loopback")

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                startListener(
                    ports: preferredPorts,
                    queue: queue
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    private func startListener(
        ports: [UInt16],
        queue: DispatchQueue
    ) {
        do {
            let listener: NWListener
            if let portValue = ports.first, let port = NWEndpoint.Port(rawValue: portValue) {
                listener = try NWListener(using: .tcp, on: port)
            } else {
                listener = try NWListener(using: .tcp, on: .any)
            }
            self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard let port = listener?.port else {
                            self.finish(.failure(UsageProviderError.oauthUnavailable("OAuth callback port was unavailable.")))
                            return
                        }
                        guard let url = self.authorizationURLBuilder?(port.rawValue) else {
                            self.finish(.failure(UsageProviderError.oauthUnavailable("OAuth authorization URL was unavailable.")))
                            return
                        }
                        self.startWebSession(url: url)
                    case let .failed(error):
                        listener?.cancel()
                        if ports.count > 1 {
                            self.startListener(
                                ports: Array(ports.dropFirst()),
                                queue: queue
                            )
                        } else {
                            self.finish(.failure(error))
                        }
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.receiveCallback(on: connection, queue: queue)
            }
            listener.start(queue: queue)
        } catch {
            if ports.count > 1 {
                startListener(
                    ports: Array(ports.dropFirst()),
                    queue: queue
                )
            } else {
                finish(.failure(error))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func startWebSession(url: URL) {
        guard webSession == nil else { return }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                let mapped: Error = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    ? UsageProviderError.authenticationCancelled
                    : error
                self?.finish(.failure(mapped))
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        webSession = session
        guard session.start() else {
            finish(.failure(UsageProviderError.oauthUnavailable("The system browser session could not start.")))
            return
        }
    }

    nonisolated private func receiveCallback(on connection: NWConnection, queue: DispatchQueue) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in self.finish(.failure(error)) }
                return
            }
            guard let data, let request = String(data: data, encoding: .utf8),
                  let firstLine = request.split(separator: "\r\n").first,
                  let target = firstLine.split(separator: " ").dropFirst().first,
                  let url = URL(string: "http://localhost\(target)")
            else {
                Task { @MainActor in self.finish(.failure(UsageProviderError.invalidOAuthCallback)) }
                return
            }

            let body = "<html><body style='font-family:-apple-system;padding:40px;background:#0b0f16;color:white'><h2>Connected</h2><p>You can return to QuotaGlance.</p></body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            Task { @MainActor in
                guard URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "state" })?.value == self.expectedState
                else {
                    self.finish(.failure(UsageProviderError.invalidOAuthCallback))
                    return
                }
                self.finish(.success(url))
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        listener?.cancel()
        listener = nil
        webSession?.cancel()
        webSession = nil
        authorizationURLBuilder = nil
        continuation.resume(with: result)
    }
}
