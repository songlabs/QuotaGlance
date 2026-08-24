import Foundation
import QuotaGlanceCore
import Security

@MainActor
final class KeychainCredentialStore {
    private let service = "com.songlabs.QuotaGlance.oauth"

    func contains(_ provider: AIProvider, accountIdentifier: UUID) -> Bool {
        (try? load(provider, accountIdentifier: accountIdentifier)) != nil
    }

    func load(_ provider: AIProvider, accountIdentifier: UUID) throws -> OAuthCredential? {
        try load(accountName: accountName(provider, accountIdentifier: accountIdentifier))
    }

    func save(_ credential: OAuthCredential, accountIdentifier: UUID) throws {
        try save(credential, accountName: accountName(credential.provider, accountIdentifier: accountIdentifier))
    }

    func delete(_ provider: AIProvider, accountIdentifier: UUID) throws {
        let status = SecItemDelete(baseQuery(accountName(provider, accountIdentifier: accountIdentifier)) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw UsageProviderError.keychain(status)
        }
    }

    func legacyCredential(for provider: AIProvider) throws -> OAuthCredential? {
        try load(accountName: provider.rawValue)
    }

    func matchesExistingRemoteAccount(
        provider: AIProvider,
        accountIdentifier: UUID,
        existingAccountIdentifiers: [UUID]
    ) throws -> Bool {
        guard let remoteAccountID = try load(provider, accountIdentifier: accountIdentifier)?.accountID else {
            return false
        }
        for existingIdentifier in existingAccountIdentifiers {
            if try load(provider, accountIdentifier: existingIdentifier)?.accountID == remoteAccountID {
                return true
            }
        }
        return false
    }

    private func load(accountName: String) throws -> OAuthCredential? {
        var query = baseQuery(accountName)
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

    private func save(_ credential: OAuthCredential, accountName: String) throws {
        let data = try JSONEncoder().encode(credential)
        let query = baseQuery(accountName)
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

    private func accountName(_ provider: AIProvider, accountIdentifier: UUID) -> String {
        "\(provider.rawValue).\(accountIdentifier.uuidString.lowercased())"
    }

    private func baseQuery(_ accountName: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName,
        ]
    }
}

@MainActor
final class AccountRegistry {
    static let accountsKey = "providerAccounts.v1"
    static let legacyMigrationKeyPrefix = "providerAccounts.legacyMigrated."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadMigratingLegacyCredentials(using credentials: KeychainCredentialStore) throws -> [ProviderAccount] {
        var accounts = load()

        for provider in AIProvider.allCases
        where !accounts.contains(where: { $0.provider == provider })
            && !defaults.bool(forKey: legacyMigrationKey(for: provider)) {
            guard let legacy = try credentials.legacyCredential(for: provider) else { continue }
            let account = ProviderAccount(
                id: UUID(),
                provider: provider,
                ordinal: nextOrdinal(for: provider, in: accounts)
            )

            // Copy first and publish the account index only after the account-scoped
            // Keychain item exists. The legacy item is intentionally retained.
            try credentials.save(legacy, accountIdentifier: account.id)
            accounts.append(account)
            save(accounts)
            defaults.set(true, forKey: legacyMigrationKey(for: provider))
        }

        return accounts
    }

    func load() -> [ProviderAccount] {
        guard let data = defaults.data(forKey: Self.accountsKey),
              let accounts = try? JSONDecoder().decode([ProviderAccount].self, from: data)
        else { return [] }
        return accounts
    }

    func add(_ account: ProviderAccount, to accounts: inout [ProviderAccount]) {
        accounts.append(account)
        save(accounts)
    }

    func update(_ account: ProviderAccount, in accounts: inout [ProviderAccount]) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        save(accounts)
    }

    func remove(_ account: ProviderAccount, from accounts: inout [ProviderAccount]) {
        accounts.removeAll { $0.id == account.id }
        save(accounts)
    }

    func makeAccount(for provider: AIProvider, in accounts: [ProviderAccount]) -> ProviderAccount {
        ProviderAccount(
            id: UUID(),
            provider: provider,
            ordinal: nextOrdinal(for: provider, in: accounts)
        )
    }

    private func nextOrdinal(for provider: AIProvider, in accounts: [ProviderAccount]) -> Int {
        (accounts.filter { $0.provider == provider }.map(\.ordinal).max() ?? 0) + 1
    }

    private func save(_ accounts: [ProviderAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: Self.accountsKey)
    }

    private func legacyMigrationKey(for provider: AIProvider) -> String {
        Self.legacyMigrationKeyPrefix + provider.rawValue
    }
}
