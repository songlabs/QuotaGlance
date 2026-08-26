import Foundation

public struct ClaudeOAuthAccount: Decodable, Equatable, Sendable {
    public let uuid: String?
    public let name: String?
    public let emailAddress: String?

    public var identityLabel: String? {
        for candidate in [name, emailAddress] {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case emailAddress = "email_address"
    }
}

public struct ClaudeOAuthOrganization: Decodable, Equatable, Sendable {
    public let uuid: String?
}
