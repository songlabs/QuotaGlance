import Foundation
import Observation
import QuotaGlanceCore
import WidgetKit

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case korean = "ko"

    static let defaultsKey = "appLanguage"

    var id: String { rawValue }

    var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }

    func displayName(locale: Locale) -> String {
        switch self {
        case .system: AppLocalization.string("System Language", locale: locale)
        case .japanese: "日本語"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .korean: "한국어"
        }
    }
}

enum PresentationError: Equatable {
    case network
    case reconnect
    case schemaChanged
    case rateLimited
    case alreadyConnected
    case generic

    init(_ error: Error) {
        guard let providerError = error as? UsageProviderError else {
            self = .generic
            return
        }
        switch providerError {
        case .network:
            self = .network
        case .tokenExpired, .noAccount:
            self = .reconnect
        case .schemaChanged:
            self = .schemaChanged
        case let .rejected(statusCode) where statusCode == 429:
            self = .rateLimited
        case .accountAlreadyConnected:
            self = .alreadyConnected
        default:
            self = .generic
        }
    }

    func message(locale: Locale) -> String {
        switch self {
        case .network:
            AppLocalization.string("Unable to refresh. Check your connection.", locale: locale)
        case .reconnect:
            AppLocalization.string("Session expired. Connect again.", locale: locale)
        case .schemaChanged:
            AppLocalization.string("Provider response changed. Cached data is preserved.", locale: locale)
        case .rateLimited:
            AppLocalization.string("Provider rate-limited refresh. Try again later.", locale: locale)
        case .alreadyConnected:
            AppLocalization.string("This account is already connected.", locale: locale)
        case .generic:
            AppLocalization.string("Something went wrong. Try again.", locale: locale)
        }
    }
}

struct ProviderPresentation: Equatable {
    var account: ProviderAccount
    var isConnected: Bool
    var snapshot: UsageSnapshot?
    var isRefreshing: Bool
    var error: PresentationError?

    var provider: AIProvider { account.provider }
}

@Observable
@MainActor
final class DashboardStore {
    private let providers: [AIProvider: any UsageProvider]
    private let credentials: KeychainCredentialStore
    private let registry: AccountRegistry
    private let cache: any SnapshotCaching
    private let watchSync: any PhoneWatchSynchronizing
    private let settingsDefaults: UserDefaults
    private let cacheLifetime: TimeInterval = 5 * 60

    var accounts: [ProviderAccount]
    var states: [UUID: ProviderPresentation]
    var providerErrors: [AIProvider: PresentationError] = [:]
    var connectingProviders: Set<AIProvider> = []
    var isShowingSettings = false
    private(set) var watchAccountIdentifiers: [UUID]
    var appLanguage: AppLanguage {
        didSet {
            settingsDefaults.set(appLanguage.rawValue, forKey: AppLanguage.defaultsKey)
            publishSnapshots()
        }
    }

    init(
        providers: [AIProvider: any UsageProvider],
        credentials: KeychainCredentialStore,
        registry: AccountRegistry,
        cache: any SnapshotCaching,
        watchSync: any PhoneWatchSynchronizing,
        settingsDefaults: UserDefaults = .standard,
        migrateLegacyCredentials: Bool = true
    ) {
        self.providers = providers
        self.credentials = credentials
        self.registry = registry
        self.cache = cache
        self.watchSync = watchSync
        self.settingsDefaults = settingsDefaults
        appLanguage = settingsDefaults.string(forKey: AppLanguage.defaultsKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system

        let loadedAccounts: [ProviderAccount]
        if migrateLegacyCredentials {
            do {
                loadedAccounts = try registry.loadMigratingLegacyCredentials(using: credentials)
            } catch {
                loadedAccounts = registry.load()
            }
        } else {
            loadedAccounts = registry.load()
        }
        accounts = loadedAccounts

        let cachedSnapshots = cache.load()?.snapshots ?? []
        var initialStates: [UUID: ProviderPresentation] = [:]
        for account in loadedAccounts {
            let exact = cachedSnapshots.first { $0.accountIdentifier == account.id }
            let isFirstProviderAccount = loadedAccounts.first(where: { $0.provider == account.provider })?.id == account.id
            let legacy = isFirstProviderAccount
                ? cachedSnapshots.first { $0.provider == account.provider && $0.accountIdentifier == nil }
                : nil
            let snapshot = (exact ?? legacy)?.assigned(to: account.id)
            initialStates[account.id] = ProviderPresentation(
                account: account,
                isConnected: providers[account.provider]?.isConnected(accountIdentifier: account.id) ?? false,
                snapshot: snapshot,
                isRefreshing: false,
                error: nil
            )
        }
        states = initialStates

        for provider in AIProvider.allCases
        where cache.selectedAccountIdentifier(for: provider) == nil {
            cache.setSelectedAccountIdentifier(
                loadedAccounts.first(where: { $0.provider == provider })?.id,
                for: provider
            )
        }

        if cache.watchAccountIdentifiers() == nil {
            let migratedSelection = AIProvider.allCases.compactMap {
                cache.selectedAccountIdentifier(for: $0)
            }
            if !migratedSelection.isEmpty {
                cache.setWatchAccountIdentifiers(migratedSelection)
            }
        }
        let availableIdentifiers = Set(loadedAccounts.map(\.id))
        watchAccountIdentifiers = (cache.watchAccountIdentifiers() ?? [])
            .filter { availableIdentifiers.contains($0) }

        watchSync.setRefreshHandler { [weak self] in
            guard let self else { return false }
            return await self.refreshAllForWatch()
        }
        publishSnapshots()
    }

    var defaultProvider: AIProvider {
        get { (cache as? AppGroupSnapshotCache)?.defaultProvider ?? .codex }
        set {
            (cache as? AppGroupSnapshotCache)?.defaultProvider = newValue
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    var displayLimit: QuotaDisplayLimit {
        get { (cache as? AppGroupSnapshotCache)?.displayLimit ?? .fiveHour }
        set {
            (cache as? AppGroupSnapshotCache)?.displayLimit = newValue
            publishSnapshots()
        }
    }

    func accounts(for provider: AIProvider) -> [ProviderAccount] {
        accounts.filter { $0.provider == provider }.sorted { $0.ordinal < $1.ordinal }
    }

    func selectedAccountIdentifier(for provider: AIProvider) -> UUID? {
        let available = accounts(for: provider)
        if let selected = cache.selectedAccountIdentifier(for: provider),
           available.contains(where: { $0.id == selected }) {
            return selected
        }
        return available.first?.id
    }

    func selectAccount(_ accountIdentifier: UUID, for provider: AIProvider) {
        guard accounts.contains(where: { $0.id == accountIdentifier && $0.provider == provider }) else { return }
        cache.setSelectedAccountIdentifier(accountIdentifier, for: provider)
        publishSnapshots()
    }

    func isSelectedForWatch(_ accountIdentifier: UUID) -> Bool {
        watchAccountIdentifiers.contains(accountIdentifier)
    }

    func canToggleWatchSelection(_ accountIdentifier: UUID) -> Bool {
        let selection = watchAccountIdentifiers
        if selection.contains(accountIdentifier) {
            return true
        }
        return selection.count < WatchAccountSelection.maximumCount
    }

    @discardableResult
    func toggleWatchSelection(_ accountIdentifier: UUID) -> Bool {
        guard accounts.contains(where: { $0.id == accountIdentifier }) else { return false }
        let current = watchAccountIdentifiers
        let updated: [UUID]
        if current.contains(accountIdentifier) {
            updated = current.filter { $0 != accountIdentifier }
        } else {
            guard let added = WatchAccountSelection.adding(accountIdentifier, to: current) else {
                return false
            }
            updated = added
        }
        watchAccountIdentifiers = updated
        cache.setWatchAccountIdentifiers(updated)
        publishSnapshots()
        return true
    }

    func renameAccount(_ accountIdentifier: UUID, name: String) {
        guard let account = accounts.first(where: { $0.id == accountIdentifier }) else { return }
        let updatedAccount = account.replacingCustomDisplayName(name)
        registry.update(updatedAccount, in: &accounts)
        states[accountIdentifier]?.account = updatedAccount
        publishSnapshots()
    }

    func refreshAll(force: Bool) async {
        for account in accounts where states[account.id]?.isConnected == true {
            if !force,
               let updatedAt = states[account.id]?.snapshot?.updatedAt,
               Date().timeIntervalSince(updatedAt) <= cacheLifetime {
                continue
            }
            await refresh(account.id)
        }
    }

    private func refreshAllForWatch() async -> Bool {
        let connectedAccounts = accounts.filter { states[$0.id]?.isConnected == true }
        guard !connectedAccounts.isEmpty else { return false }
        var succeeded = true
        for account in connectedAccounts {
            await refresh(account.id)
            if states[account.id]?.error != nil {
                succeeded = false
            }
        }
        return succeeded
    }

    func backfillAccountIdentityLabels() async {
        var didUpdateAccount = false
        for account in accounts where account.identityLabel == nil && states[account.id]?.isConnected == true {
            guard let provider = providers[account.provider] else { continue }
            do {
                guard let identityLabel = try await provider.accountIdentityLabel(accountIdentifier: account.id) else {
                    continue
                }
                let updatedAccount = account.replacingIdentityLabel(identityLabel)
                registry.update(updatedAccount, in: &accounts)
                states[account.id]?.account = updatedAccount
                didUpdateAccount = true
            } catch {
                // Identity enrichment is best effort and must not block usage refresh.
            }
        }
        if didUpdateAccount {
            publishSnapshots()
        }
    }

    func refresh(_ accountIdentifier: UUID) async {
        guard let account = accounts.first(where: { $0.id == accountIdentifier }),
              let usageProvider = providers[account.provider],
              states[accountIdentifier]?.isConnected == true,
              states[accountIdentifier]?.isRefreshing == false
        else { return }

        states[accountIdentifier]?.isRefreshing = true
        states[accountIdentifier]?.error = nil
        defer { states[accountIdentifier]?.isRefreshing = false }

        do {
            let snapshot = try await usageProvider.refreshUsage(accountIdentifier: accountIdentifier)
                .assigned(to: accountIdentifier)
            states[accountIdentifier]?.snapshot = snapshot
            states[accountIdentifier]?.error = nil
            publishSnapshots()
        } catch {
            if requiresReconnect(error) {
                states[accountIdentifier]?.isConnected = false
            }
            states[accountIdentifier]?.error = PresentationError(error)
        }
    }

    func addAccount(_ provider: AIProvider) async {
        guard let usageProvider = providers[provider], !connectingProviders.contains(provider) else { return }
        let pendingAccount = registry.makeAccount(for: provider, in: accounts)
        connectingProviders.insert(provider)
        providerErrors[provider] = nil
        registry.add(pendingAccount, to: &accounts)
        states[pendingAccount.id] = ProviderPresentation(
            account: pendingAccount,
            isConnected: false,
            snapshot: nil,
            isRefreshing: true,
            error: nil
        )
        defer { connectingProviders.remove(provider) }

        do {
            let identityLabel = try await usageProvider.connect(accountIdentifier: pendingAccount.id)
            let existingIdentifiers = accounts
                .filter { $0.provider == provider && $0.id != pendingAccount.id }
                .map(\.id)
            if try credentials.matchesExistingRemoteAccount(
                provider: provider,
                accountIdentifier: pendingAccount.id,
                existingAccountIdentifiers: existingIdentifiers
            ) {
                try await usageProvider.disconnect(accountIdentifier: pendingAccount.id)
                throw UsageProviderError.accountAlreadyConnected
            }
            let account = pendingAccount.replacingIdentityLabel(identityLabel)
            registry.update(account, in: &accounts)
            states[account.id] = ProviderPresentation(
                account: account,
                isConnected: true,
                snapshot: nil,
                isRefreshing: false,
                error: nil
            )
            if cache.selectedAccountIdentifier(for: provider) == nil {
                cache.setSelectedAccountIdentifier(account.id, for: provider)
            }
            if cache.watchAccountIdentifiers() == nil {
                watchAccountIdentifiers = [account.id]
                cache.setWatchAccountIdentifiers(watchAccountIdentifiers)
            }
            await refresh(account.id)
        } catch {
            if usageProvider.isConnected(accountIdentifier: pendingAccount.id) {
                states[pendingAccount.id]?.isConnected = true
                states[pendingAccount.id]?.isRefreshing = false
                states[pendingAccount.id]?.error = PresentationError(error)
            } else {
                registry.remove(pendingAccount, from: &accounts)
                states[pendingAccount.id] = nil
            }
            providerErrors[provider] = PresentationError(error)
        }
    }

    func reconnect(_ accountIdentifier: UUID) async {
        guard let account = accounts.first(where: { $0.id == accountIdentifier }),
              let usageProvider = providers[account.provider]
        else { return }

        states[accountIdentifier]?.isRefreshing = true
        states[accountIdentifier]?.error = nil
        do {
            let identityLabel = try await usageProvider.connect(accountIdentifier: accountIdentifier)
            let updatedAccount = account.replacingIdentityLabel(identityLabel)
            registry.update(updatedAccount, in: &accounts)
            states[accountIdentifier]?.isConnected = true
            states[accountIdentifier]?.account = updatedAccount
            states[accountIdentifier]?.isRefreshing = false
            if cache.watchAccountIdentifiers() == nil {
                watchAccountIdentifiers = [accountIdentifier]
                cache.setWatchAccountIdentifiers(watchAccountIdentifiers)
            }
            await refresh(accountIdentifier)
        } catch {
            states[accountIdentifier]?.isRefreshing = false
            states[accountIdentifier]?.isConnected = usageProvider.isConnected(accountIdentifier: accountIdentifier)
            states[accountIdentifier]?.error = PresentationError(error)
        }
    }

    func deleteAccount(_ accountIdentifier: UUID) async {
        guard let account = accounts.first(where: { $0.id == accountIdentifier }),
              let usageProvider = providers[account.provider]
        else { return }

        do {
            try await usageProvider.disconnect(accountIdentifier: accountIdentifier)
            registry.remove(account, from: &accounts)
            states[accountIdentifier] = nil
            try cache.remove(accountIdentifier: accountIdentifier)

            if cache.selectedAccountIdentifier(for: account.provider) == accountIdentifier {
                cache.setSelectedAccountIdentifier(accounts(for: account.provider).first?.id, for: account.provider)
            }
            if let watchSelection = cache.watchAccountIdentifiers() {
                watchAccountIdentifiers = watchSelection.filter { $0 != accountIdentifier }
                cache.setWatchAccountIdentifiers(watchAccountIdentifiers)
            }
            publishSnapshots()
        } catch {
            states[accountIdentifier]?.error = PresentationError(error)
        }
    }

    func loadPreview(_ previews: [ProviderPresentation]) {
        accounts = previews.map(\.account)
        states = Dictionary(uniqueKeysWithValues: previews.map { ($0.account.id, $0) })
    }

    private func publishSnapshots() {
        let snapshots = accounts.compactMap { states[$0.id]?.snapshot }
        let envelope = SnapshotEnvelope(
            snapshots: snapshots,
            displayLimit: displayLimit,
            accounts: accounts.map { account in
                AccountDisplayMetadata(
                    id: account.id,
                    provider: account.provider,
                    ordinal: account.ordinal,
                    displayName: accountDisplayName(account)
                )
            },
            watchAccountIdentifiers: watchAccountIdentifiers
        )
        try? cache.save(envelope)
        watchSync.send(envelope)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func accountDisplayName(_ account: ProviderAccount) -> String {
        account.displayName(fallback: AppLocalization.string(
            "account.number",
            defaultValue: "Account %lld",
            locale: appLanguage.locale,
            arguments: [account.ordinal]
        ))
    }

    private func requiresReconnect(_ error: Error) -> Bool {
        guard let error = error as? UsageProviderError else { return false }
        return error == .tokenExpired || error == .noAccount
    }
}
