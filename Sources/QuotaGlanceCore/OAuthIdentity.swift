import Foundation

public struct ClaudeOAuthAccount: Decodable, Equatable, Sendable {
    public let uuid: String?
    public let emailAddress: String?

    public var identityLabel: String? {
        guard let emailAddress else { return nil }
        let trimmedEmail = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmail.isEmpty ? nil : trimmedEmail
    }

    enum CodingKeys: String, CodingKey {
        case uuid
        case emailAddress = "email_address"
    }
}

public struct ClaudeOAuthOrganization: Decodable, Equatable, Sendable {
    public let uuid: String?
}
