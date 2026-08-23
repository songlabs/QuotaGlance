import Foundation
import QuotaGlanceCore

struct OAuthCredential: Codable, Equatable {
    let provider: AIProvider
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let accountID: String?
    let scopes: [String]

    func replacing(
        accessToken: String?,
        refreshToken: String?,
        expiresAt: Date?,
        accountID: String? = nil,
        scopes: [String]? = nil
    ) -> OAuthCredential {
        OAuthCredential(
            provider: provider,
            accessToken: accessToken ?? self.accessToken,
            refreshToken: refreshToken ?? self.refreshToken,
            expiresAt: expiresAt ?? self.expiresAt,
            accountID: accountID ?? self.accountID,
            scopes: scopes ?? self.scopes
        )
    }
}
