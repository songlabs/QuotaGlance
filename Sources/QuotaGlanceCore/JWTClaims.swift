import Foundation

public enum JWTClaims {
    private static let openAIAuthClaim = "https://api.openai.com/auth"
    private static let openAIProfileClaim = "https://api.openai.com/profile"

    public static func chatGPTAccountID(in token: String) -> String? {
        let claims = payload(in: token)
        if let authClaims = claims?[openAIAuthClaim] as? [String: Any],
           let accountID = authClaims["chatgpt_account_id"] as? String {
            return accountID
        }
        return claims?["chatgpt_account_id"] as? String
    }

    public static func expiration(in token: String) -> Date? {
        guard let value = payload(in: token)?["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    public static func accountDisplayName(in token: String) -> String? {
        guard let claims = payload(in: token) else { return nil }
        let profiles = [claims, claims[openAIProfileClaim] as? [String: Any]].compactMap { $0 }
        for key in ["name", "preferred_username", "email"] {
            for profile in profiles {
                if let value = readableString(profile[key]) { return value }
            }
        }
        return nil
    }

    private static func readableString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func payload(in token: String) -> [String: Any]? {
        let pieces = token.split(separator: ".")
        guard pieces.count > 1 else { return nil }
        var encoded = String(pieces[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded.append(String(repeating: "=", count: (4 - encoded.count % 4) % 4))
        guard let data = Data(base64Encoded: encoded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }
}
