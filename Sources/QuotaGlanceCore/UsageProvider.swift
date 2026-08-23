import Foundation

@MainActor
public protocol UsageProvider: AnyObject {
    var provider: AIProvider { get }
    var isConnected: Bool { get }

    func connect() async throws
    func disconnect() async throws
    func refreshUsage() async throws -> UsageSnapshot
}
public enum UsageProviderError: Error, Equatable, Sendable {
    case authenticationCancelled
    case noAccount
    case tokenExpired
    case network
    case rejected(statusCode: Int)
    case schemaChanged
    case invalidOAuthCallback
    case oauthUnavailable(String)
    case keychain(Int32)
}

extension UsageProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authenticationCancelled:
            "Authentication was cancelled."
        case .noAccount:
            "No connected account."
        case .tokenExpired:
            "Your session expired. Connect again."
        case .network:
            "Unable to reach the provider."
        case let .rejected(statusCode):
            "The provider returned HTTP \(statusCode)."
        case .schemaChanged:
            "The provider response format changed."
        case .invalidOAuthCallback:
            "The OAuth callback could not be verified."
        case let .oauthUnavailable(reason):
            reason
        case let .keychain(status):
            "Keychain operation failed (\(status))."
        }
    }
}
