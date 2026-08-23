import Foundation
import QuotaGlanceCore
import Security

@MainActor
final class KeychainCredentialStore {
    private let service = "com.songlabs.QuotaGlance.oauth"

    func contains(_ provider: AIProvider) -> Bool {
        (try? load(provider)) != nil
    }

    func load(_ provider: AIProvider) throws -> OAuthCredential? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw UsageProviderError.keychain(status)
        }

        do {
            return try JSONDecoder().decode(OAuthCredential.self, from: data)
        } catch {
            throw UsageProviderError.tokenExpired
        }
    }

    func save(_ credential: OAuthCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let query = baseQuery(credential.provider)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw UsageProviderError.keychain(updateStatus)
        }

        var insert = query
        attributes.forEach { insert[$0.key] = $0.value }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw UsageProviderError.keychain(addStatus)
        }
    }

    func delete(_ provider: AIProvider) throws {
        let status = SecItemDelete(baseQuery(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw UsageProviderError.keychain(status)
        }
    }

    private func baseQuery(_ provider: AIProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }
}
