import Foundation

@MainActor
public protocol UsageProvider: AnyObject {
    var provider: AIProvider { get }

    func isConnected(accountIdentifier: UUID) -> Bool
    func connect(accountIdentifier: UUID) async throws -> String?
    func accountIdentityLabel(accountIdentifier: UUID) async throws -> String?
    func disconnect(accountIdentifier: UUID) async throws
    func refreshUsage(accountIdentifier: UUID) async throws -> UsageSnapshot
}

public extension UsageProvider {
    func accountIdentityLabel(accountIdentifier: UUID) async throws -> String? { nil }
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
    case accountAlreadyConnected
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
        case .accountAlreadyConnected:
            "This provider account is already connected."
        case let .keychain(status):
            "Keychain operation failed (\(status))."
        }
    }
}
