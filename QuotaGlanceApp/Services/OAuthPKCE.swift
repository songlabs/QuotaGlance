import CryptoKit
import Foundation
import QuotaGlanceCore
import Security

struct OAuthPKCE {
    let verifier: String
    let challenge: String

    static func make() throws -> OAuthPKCE {
        let bytes = try secureRandomBytes(count: 64)
        let verifier = Data(bytes).base64URLEncodedString()
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return OAuthPKCE(verifier: verifier, challenge: Data(digest).base64URLEncodedString())
    }

    static func state() throws -> String {
        Data(try secureRandomBytes(count: 32)).base64URLEncodedString()
    }

    private static func secureRandomBytes(count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw UsageProviderError.keychain(status)
        }
        return bytes
    }
}
private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
