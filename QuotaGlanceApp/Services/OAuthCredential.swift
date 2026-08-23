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
enum JWTClaims {
    static func string(_ key: String, in token: String) -> String? {
        payload(in: token)?[key] as? String
    }

    static func expiration(in token: String) -> Date? {
        guard let value = payload(in: token)?["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    private static func payload(in token: String) -> [String: Any]? {
        let pieces = token.split(separator: ".")
        guard pieces.count > 1 else { return nil }
        var encoded = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded.append(String(repeating: "=", count: (4 - encoded.count % 4) % 4))
        guard let data = Data(base64Encoded: encoded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }
}
