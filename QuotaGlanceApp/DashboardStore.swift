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

private struct ProductionDashboardState {
    let accounts: [ProviderAccount]
    let states: [UUID: ProviderPresentation]
    let providerErrors: [AIProvider: PresentationError]
    let selectedAccountIdentifiers: [AIProvider: UUID]
    let watchAccountIdentifiers: [UUID]
    let appLanguage: AppLanguage
    let wasForegroundAutomaticRefreshActive: Bool
}

@Observable
@MainActor
final class DashboardStore {
    let purchaseManager: PurchaseManager
    private let providers: [AIProvider: any UsageProvider]
    private let credentials: KeychainCredentialStore
    private let registry: AccountRegistry
    private let cache: any SnapshotCaching
    private let watchSync: any PhoneWatchSynchronizing
    private let settingsDefaults: UserDefaults

    var accounts: [ProviderAccount]
    var states: [UUID: ProviderPresentation]
    var providerErrors: [AIProvider: PresentationError] = [:]
    var connectingProviders: Set<AIProvider> = []
    var isShowingSettings = false
    var isShowingUpgrade = false
    var isShowingAppReviewDemo = false
    private(set) var isAppReviewDemoEnabled = false
    private(set) var appReviewDemoAccessLevel: AccessLevel = .pro
    private(set) var refreshInterval: AutomaticRefreshInterval {
        didSet {
            AutomaticRefreshPreferences.save(refreshInterval, to: settingsDefaults)
            restartForegroundAutomaticRefresh()
            automaticRefreshConfigurationDidChange?()
        }
    }
    private(set) var watchAccountIdentifiers: [UUID]
    private(set) var selectedAccountIdentifiers: [AIProvider: UUID]
    private var lastRefreshAttempts: [UUID: Date] = [:]
    private var activeProductionOperationCount = 0
    private var foregroundAutomaticRefreshTask: Task<Void, Never>?
    private(set) var isForegroundAutomaticRefreshActive = false
    private var productionStateBeforeDemo: ProductionDashboardState?
    private var productionEnvelopeBeforeDemo: SnapshotEnvelope?
    private var appReviewDemoReferenceDate = Date()
    private var appReviewDemoDefaultProvider: AIProvider = .codex
    private var appReviewDemoDisplayLimit: QuotaDisplayLimit = .fiveHour
    private var appReviewDemoRefreshInterval: AutomaticRefreshInterval = .fourHours
    private var suppressAppLanguageSideEffects = false
    var automaticRefreshConfigurationDidChange: (() -> Void)?
    var appLanguage: AppLanguage {
        didSet {
            guard !suppressAppLanguageSideEffects else { return }
            if !isAppReviewDemoEnabled {
                settingsDefaults.set(appLanguage.rawValue, forKey: AppLanguage.defaultsKey)
            }
            publishSnapshots()
        }
    }

    init(
        providers: [AIProvider: any UsageProvider],
        credentials: KeychainCredentialStore,
        registry: AccountRegistry,
        cache: any SnapshotCaching,
        watchSync: any PhoneWatchSynchronizing,
        purchaseManager: PurchaseManager = PurchaseManager(),
        settingsDefaults: UserDefaults = .standard,
        migrateLegacyCredentials: Bool = true
    ) {
        self.providers = providers
        self.credentials = credentials
        self.registry = registry
        self.cache = cache
        self.watchSync = watchSync
        self.purchaseManager = purchaseManager
        self.settingsDefaults = settingsDefaults
        refreshInterval = AutomaticRefreshPreferences.load(from: settingsDefaults)
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

        var initialSelectedAccountIdentifiers = Dictionary(uniqueKeysWithValues: AIProvider.allCases.compactMap { provider in
            cache.selectedAccountIdentifier(for: provider).map { (provider, $0) }
        })

        let initialSnapshotRecovery = cache.recoverInterruptedAppReviewDemoSnapshot()
        let cachedSnapshots = initialSnapshotRecovery.envelope?.snapshots ?? []
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

        let legacyWatchSelection = AIProvider.allCases.compactMap {
            cache.selectedAccountIdentifier(for: $0)
        }
        for provider in AIProvider.allCases
        where cache.selectedAccountIdentifier(for: provider) == nil {
            if let accountIdentifier = loadedAccounts.first(where: { $0.provider == provider })?.id {
                initialSelectedAccountIdentifiers[provider] = accountIdentifier
                cache.setSelectedAccountIdentifier(accountIdentifier, for: provider)
            }
        }
        selectedAccountIdentifiers = initialSelectedAccountIdentifiers

        if cache.watchAccountIdentifiers() == nil {
            let initialWatchSelection = WatchAccountSelection.initial(
                accountIdentifiers: loadedAccounts.map(\.id),
                legacySelectedAccountIdentifiers: legacyWatchSelection
            )
            if !initialWatchSelection.isEmpty {
                cache.setWatchAccountIdentifiers(initialWatchSelection)
            }
        }
        let availableIdentifiers = Set(loadedAccounts.map(\.id))
        watchAccountIdentifiers = (cache.watchAccountIdentifiers() ?? [])
            .filter { availableIdentifiers.contains($0) }

        watchSync.setRefreshHandler { [weak self] in
            guard let self else { return false }
            return await self.refreshAllForWatch()
        }
        if initialSnapshotRecovery.didRecover,
           let restoredProductionEnvelope = initialSnapshotRecovery.envelope {
            watchSync.send(restoredProductionEnvelope)
            WidgetCenter.shared.reloadAllTimelines()
        }
        purchaseManager.entitlementDidChange = { [weak self] in
            guard let self else { return }
            self.publishSnapshots()
            self.restartForegroundAutomaticRefresh()
            self.automaticRefreshConfigurationDidChange?()
        }
    }

    var defaultProvider: AIProvider {
        get {
            if isAppReviewDemoEnabled { return appReviewDemoDefaultProvider }
            return (cache as? AppGroupSnapshotCache)?.defaultProvider ?? .codex
        }
        set {
            if isAppReviewDemoEnabled {
                appReviewDemoDefaultProvider = newValue
                publishSnapshots()
                return
            }
            (cache as? AppGroupSnapshotCache)?.defaultProvider = newValue
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    var displayLimit: QuotaDisplayLimit {
        if isAppReviewDemoEnabled { return appReviewDemoDisplayLimit }
        return (cache as? AppGroupSnapshotCache)?.displayLimit ?? .fiveHour
    }

    var effectiveDisplayLimit: QuotaDisplayLimit {
        displayLimit.effective(for: accessLevel)
    }

    func accounts(for provider: AIProvider) -> [ProviderAccount] {
        let matching = accounts.filter { $0.provider == provider }.sorted { $0.ordinal < $1.ordinal }
        guard !hasProFeatures else { return matching }
        guard let freeAccount = accounts.first,
              freeAccount.provider == provider else { return [] }
        return matching.filter { $0.id == freeAccount.id }
    }

    var accessLevel: AccessLevel {
        isAppReviewDemoEnabled ? appReviewDemoAccessLevel : purchaseManager.accessLevel
    }
    var hasProFeatures: Bool { accessLevel.hasProFeatures }
    var canAddAccount: Bool {
        !isAppReviewDemoEnabled && (hasProFeatures || accounts.isEmpty)
    }
    var canManageAccounts: Bool { !isAppReviewDemoEnabled }
    var canEnableAppReviewDemo: Bool {
        !isAppReviewDemoEnabled
            && purchaseManager.isEntitlementLoaded
            && activeProductionOperationCount == 0
    }
    var effectiveRefreshInterval: AutomaticRefreshInterval {
        let storedInterval = isAppReviewDemoEnabled ? appReviewDemoRefreshInterval : refreshInterval
        return storedInterval.effective(for: accessLevel)
    }
    var effectiveWatchAccountIdentifiers: [UUID] {
        hasProFeatures
            ? watchAccountIdentifiers
            : accounts.first.map { [$0.id] } ?? []
    }

    func requirePro() {
        if isAppReviewDemoEnabled {
            isShowingAppReviewDemo = true
        } else {
            isShowingUpgrade = true
        }
    }

    func enableAppReviewDemo() {
        guard canEnableAppReviewDemo else { return }
        let productionEnvelope: SnapshotEnvelope?
        do {
            productionEnvelope = try cache.prepareAppReviewDemoSnapshot()
        } catch {
            return
        }
        productionStateBeforeDemo = ProductionDashboardState(
            accounts: accounts,
            states: states,
            providerErrors: providerErrors,
            selectedAccountIdentifiers: selectedAccountIdentifiers,
            watchAccountIdentifiers: watchAccountIdentifiers,
            appLanguage: appLanguage,
            wasForegroundAutomaticRefreshActive: isForegroundAutomaticRefreshActive
        )
        productionEnvelopeBeforeDemo = productionEnvelope
        appReviewDemoReferenceDate = Date()
        appReviewDemoAccessLevel = .pro
        appReviewDemoDefaultProvider = .codex
        appReviewDemoDisplayLimit = .fiveHour
        appReviewDemoRefreshInterval = .fourHours
        isAppReviewDemoEnabled = true
        isShowingUpgrade = false
        stopForegroundAutomaticRefresh()

        let presentations = PreviewFactory.appReviewDemoStates(updatedAt: appReviewDemoReferenceDate)
        accounts = presentations.map(\.account)
        states = Dictionary(uniqueKeysWithValues: presentations.map { ($0.account.id, $0) })
        providerErrors = [:]
        connectingProviders = []
        selectedAccountIdentifiers = Dictionary(uniqueKeysWithValues: AIProvider.allCases.compactMap { provider in
            accounts.first(where: { $0.provider == provider }).map { (provider, $0.id) }
        })
        watchAccountIdentifiers = WatchAccountSelection.normalized([
            PreviewFactory.codexAccount.id,
            PreviewFactory.claudeAccount.id,
        ])
        publishSnapshots()
        automaticRefreshConfigurationDidChange?()
    }

    func disableAppReviewDemo() {
        guard isAppReviewDemoEnabled, let productionStateBeforeDemo else { return }
        isAppReviewDemoEnabled = false
        accounts = productionStateBeforeDemo.accounts
        states = productionStateBeforeDemo.states
        providerErrors = productionStateBeforeDemo.providerErrors
        selectedAccountIdentifiers = productionStateBeforeDemo.selectedAccountIdentifiers
        watchAccountIdentifiers = productionStateBeforeDemo.watchAccountIdentifiers
        suppressAppLanguageSideEffects = true
        appLanguage = productionStateBeforeDemo.appLanguage
        suppressAppLanguageSideEffects = false
        isForegroundAutomaticRefreshActive = productionStateBeforeDemo.wasForegroundAutomaticRefreshActive
        self.productionStateBeforeDemo = nil
        restoreProductionSharedSnapshot()
        productionEnvelopeBeforeDemo = nil
        isShowingAppReviewDemo = false
        restartForegroundAutomaticRefresh()
        automaticRefreshConfigurationDidChange?()
    }

    func setAppReviewDemoAccessLevel(_ accessLevel: AccessLevel) {
        guard isAppReviewDemoEnabled else { return }
        appReviewDemoAccessLevel = accessLevel
        publishSnapshots()
        automaticRefreshConfigurationDidChange?()
    }

    func updateRefreshInterval(_ interval: AutomaticRefreshInterval) {
        guard hasProFeatures else { return }
        if isAppReviewDemoEnabled {
            appReviewDemoRefreshInterval = interval
            automaticRefreshConfigurationDidChange?()
            return
        }
        refreshInterval = interval
    }

    func updateDisplayLimit(_ limit: QuotaDisplayLimit) {
        guard hasProFeatures else { return }
        if isAppReviewDemoEnabled {
            appReviewDemoDisplayLimit = limit
        } else {
            (cache as? AppGroupSnapshotCache)?.displayLimit = limit
        }
        publishSnapshots()
    }

    func startForegroundAutomaticRefresh() {
        guard !isAppReviewDemoEnabled else {
            stopForegroundAutomaticRefresh()
            return
        }
        isForegroundAutomaticRefreshActive = true
        restartForegroundAutomaticRefresh()
    }

    func stopForegroundAutomaticRefresh() {
        isForegroundAutomaticRefreshActive = false
        foregroundAutomaticRefreshTask?.cancel()
        foregroundAutomaticRefreshTask = nil
    }

    func refreshAccess(previousAccessLevel: AccessLevel? = nil) async {
        guard !isAppReviewDemoEnabled else {
            publishSnapshots()
            return
        }
        await purchaseManager.refreshEntitlements()
    }

    func performBackgroundAutomaticRefresh() async -> Bool {
        if isAppReviewDemoEnabled {
            reloadAppReviewDemoData()
            return true
        }
        await purchaseManager.refreshEntitlements()
        guard !Task.isCancelled else { return false }
        return await refreshAll(force: false)
    }

    func selectedAccountIdentifier(for provider: AIProvider) -> UUID? {
        let available = accounts(for: provider)
        if let selected = selectedAccountIdentifiers[provider],
           available.contains(where: { $0.id == selected }) {
            return selected
        }
        return available.first?.id
    }

    func selectAccount(_ accountIdentifier: UUID, for provider: AIProvider) {
        guard accounts.contains(where: { $0.id == accountIdentifier && $0.provider == provider }) else { return }
        selectedAccountIdentifiers[provider] = accountIdentifier
        if !isAppReviewDemoEnabled {
            cache.setSelectedAccountIdentifier(accountIdentifier, for: provider)
        }
        publishSnapshots()
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
        guard hasProFeatures else {
            requirePro()
            return false
        }
        guard accounts.contains(where: { $0.id == accountIdentifier }) else { return false }
        let current = watchAccountIdentifiers
        let updated: [UUID]
        if current.contains(accountIdentifier) {
            updated = WatchAccountSelection.removing(accountIdentifier, from: current)
        } else {
            guard let added = WatchAccountSelection.adding(accountIdentifier, to: current) else {
                return false
            }
            updated = added
        }
        watchAccountIdentifiers = updated
        if !isAppReviewDemoEnabled {
            cache.setWatchAccountIdentifiers(updated)
        }
        publishSnapshots()
        return true
    }

    func renameAccount(_ accountIdentifier: UUID, name: String) {
        guard !isAppReviewDemoEnabled else { return }
        guard let account = accounts.first(where: { $0.id == accountIdentifier }) else { return }
        let updatedAccount = account.replacingCustomDisplayName(name)
        registry.update(updatedAccount, in: &accounts)
        states[accountIdentifier]?.account = updatedAccount
        publishSnapshots()
    }

    @discardableResult
    func refreshAll(force: Bool) async -> Bool {
        if isAppReviewDemoEnabled {
            reloadAppReviewDemoData()
            return true
        }
        let now = Date()
        let activeAccounts = hasProFeatures ? accounts : Array(accounts.prefix(1))
        var succeeded = true
        for account in activeAccounts where states[account.id]?.isConnected == true {
            if !effectiveRefreshInterval.shouldRefresh(
                lastSuccessfulUpdate: states[account.id]?.snapshot?.updatedAt,
                lastRefreshAttempt: lastRefreshAttempts[account.id],
                force: force,
                now: now
            ) {
                continue
            }
            if states[account.id]?.isRefreshing == true {
                continue
            }
            if !(await refresh(account.id, reschedulesForegroundAutomaticRefresh: false)) {
                succeeded = false
            }
        }
        restartForegroundAutomaticRefresh()
        return succeeded
    }

    private func refreshAllForWatch() async -> Bool {
        if isAppReviewDemoEnabled {
            reloadAppReviewDemoData()
            return true
        }
        await purchaseManager.refreshEntitlements()
        let selected = WatchRefreshScope.accountIdentifiers(
            accounts: accounts.map(\.id),
            selectedAccountIdentifiers: watchAccountIdentifiers,
            hasProFeatures: hasProFeatures
        )
        let eligibleAccounts = accounts.filter { selected.contains($0.id) }
        let connectedAccounts = eligibleAccounts.filter { states[$0.id]?.isConnected == true }
        guard !connectedAccounts.isEmpty else { return false }
        var succeeded = true
        for account in connectedAccounts {
            if !(await refresh(account.id, reschedulesForegroundAutomaticRefresh: false)) {
                succeeded = false
            }
        }
        restartForegroundAutomaticRefresh()
        return succeeded
    }

    func backfillAccountIdentityLabels() async {
        guard !isAppReviewDemoEnabled else { return }
        activeProductionOperationCount += 1
        defer { activeProductionOperationCount -= 1 }
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

    @discardableResult
    func refresh(
        _ accountIdentifier: UUID,
        reschedulesForegroundAutomaticRefresh: Bool = true
    ) async -> Bool {
        if isAppReviewDemoEnabled {
            guard accounts.contains(where: { $0.id == accountIdentifier }) else { return false }
            reloadAppReviewDemoData()
            return true
        }
        guard let account = accounts.first(where: { $0.id == accountIdentifier }),
              let usageProvider = providers[account.provider],
              states[accountIdentifier]?.isConnected == true,
              states[accountIdentifier]?.isRefreshing == false
        else { return false }

        activeProductionOperationCount += 1
        defer { activeProductionOperationCount -= 1 }
        states[accountIdentifier]?.isRefreshing = true
        states[accountIdentifier]?.error = nil
        lastRefreshAttempts[accountIdentifier] = Date()
        defer { states[accountIdentifier]?.isRefreshing = false }

        do {
            let snapshot = try await usageProvider.refreshUsage(accountIdentifier: accountIdentifier)
                .assigned(to: accountIdentifier)
            try Task.checkCancellation()
            states[accountIdentifier]?.snapshot = snapshot
            states[accountIdentifier]?.error = nil
            publishSnapshots()
            if reschedulesForegroundAutomaticRefresh {
                restartForegroundAutomaticRefresh()
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            if requiresReconnect(error) {
                states[accountIdentifier]?.isConnected = false
            }
            states[accountIdentifier]?.error = PresentationError(error)
            if reschedulesForegroundAutomaticRefresh {
                restartForegroundAutomaticRefresh()
            }
            return false
        }
    }

    func addAccount(_ provider: AIProvider) async {
        guard !isAppReviewDemoEnabled else {
            isShowingAppReviewDemo = true
            return
        }
        guard canAddAccount else {
            requirePro()
            return
        }
        guard let usageProvider = providers[provider], !connectingProviders.contains(provider) else { return }
        activeProductionOperationCount += 1
        defer { activeProductionOperationCount -= 1 }
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
                selectedAccountIdentifiers[provider] = account.id
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
        guard !isAppReviewDemoEnabled else { return }
        guard let account = accounts.first(where: { $0.id == accountIdentifier }),
              let usageProvider = providers[account.provider]
        else { return }

        activeProductionOperationCount += 1
        defer { activeProductionOperationCount -= 1 }
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
        guard !isAppReviewDemoEnabled else { return }
        guard let account = accounts.first(where: { $0.id == accountIdentifier }),
              let usageProvider = providers[account.provider]
        else { return }

        activeProductionOperationCount += 1
        defer { activeProductionOperationCount -= 1 }
        do {
            try await usageProvider.disconnect(accountIdentifier: accountIdentifier)
            registry.remove(account, from: &accounts)
            states[accountIdentifier] = nil
            lastRefreshAttempts[accountIdentifier] = nil
            try cache.remove(accountIdentifier: accountIdentifier)

            if cache.selectedAccountIdentifier(for: account.provider) == accountIdentifier {
                let replacement = accounts(for: account.provider).first?.id
                selectedAccountIdentifiers[account.provider] = replacement
                cache.setSelectedAccountIdentifier(replacement, for: account.provider)
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

    func loadPreview(
        _ previews: [ProviderPresentation],
        watchAccountIdentifiers: [UUID] = []
    ) {
        accounts = previews.map(\.account)
        states = Dictionary(uniqueKeysWithValues: previews.map { ($0.account.id, $0) })
        self.watchAccountIdentifiers = WatchAccountSelection.normalized(watchAccountIdentifiers)
        cache.setWatchAccountIdentifiers(self.watchAccountIdentifiers)
    }

    private func publishSnapshots() {
        if !isAppReviewDemoEnabled {
            guard EntitlementPublicationPolicy.canPublish(
                isEntitlementLoaded: purchaseManager.isEntitlementLoaded
            ) else { return }
        }
        let entitledAccounts = hasProFeatures ? accounts : Array(accounts.prefix(1))
        let snapshots = entitledAccounts.compactMap { states[$0.id]?.snapshot }
        let entitledAccountIdentifiers = Set(entitledAccounts.map(\.id))
        let demoSelectedAccountIdentifiers = selectedAccountIdentifiers.filter {
            entitledAccountIdentifiers.contains($0.value)
        }
        let demoDefaultProvider = entitledAccounts.contains(where: { $0.provider == defaultProvider })
            ? defaultProvider
            : entitledAccounts.first?.provider
        let envelope = SnapshotEnvelope(
            snapshots: snapshots,
            displayLimit: effectiveDisplayLimit,
            accounts: entitledAccounts.map { account in
                AccountDisplayMetadata(
                    id: account.id,
                    provider: account.provider,
                    ordinal: account.ordinal,
                    displayName: accountDisplayName(account)
                )
            },
            watchAccountIdentifiers: effectiveWatchAccountIdentifiers,
            accessLevel: accessLevel,
            proAccessExpiresAt: accessLevel == .trial
                ? (isAppReviewDemoEnabled
                   ? appReviewDemoReferenceDate.addingTimeInterval(6 * 24 * 60 * 60)
                   : purchaseManager.trialEndsAt)
                : nil,
            isAppReviewDemo: isAppReviewDemoEnabled,
            appReviewDemoDefaultProvider: isAppReviewDemoEnabled ? demoDefaultProvider : nil,
            appReviewDemoSelectedAccountIdentifiers: isAppReviewDemoEnabled
                ? demoSelectedAccountIdentifiers
                : [:]
        )
        try? cache.save(envelope)
        watchSync.send(envelope)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func reloadAppReviewDemoData(updatedAt: Date = Date()) {
        guard isAppReviewDemoEnabled else { return }
        let presentations = PreviewFactory.appReviewDemoStates(updatedAt: updatedAt)
        accounts = presentations.map(\.account)
        states = Dictionary(uniqueKeysWithValues: presentations.map { ($0.account.id, $0) })
        publishSnapshots()
    }

    private func restoreProductionSharedSnapshot() {
        let productionEnvelope: SnapshotEnvelope
        do {
            productionEnvelope = try cache.restoreProductionSnapshotAfterAppReviewDemo()
        } catch {
            productionEnvelope = productionEnvelopeBeforeDemo ?? SnapshotEnvelope(snapshots: [])
            try? cache.save(productionEnvelope)
        }
        watchSync.send(productionEnvelope)
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

    private func restartForegroundAutomaticRefresh(now: Date = Date()) {
        foregroundAutomaticRefreshTask?.cancel()
        foregroundAutomaticRefreshTask = nil
        guard isForegroundAutomaticRefreshActive,
              !isAppReviewDemoEnabled,
              purchaseManager.isEntitlementLoaded,
              let nextRefreshDate = nextForegroundAutomaticRefreshDate(now: now)
        else { return }

        let delay = max(0, nextRefreshDate.timeIntervalSince(now))
        foregroundAutomaticRefreshTask = Task { @MainActor [weak self] in
            do {
                if delay > 0 {
                    try await Task.sleep(for: .seconds(delay))
                }
                try Task.checkCancellation()
            } catch {
                return
            }
            guard let self else { return }
            self.foregroundAutomaticRefreshTask = nil
            await self.refreshAll(force: false)
        }
    }

    private func nextForegroundAutomaticRefreshDate(now: Date) -> Date? {
        let activeAccounts = hasProFeatures ? accounts : Array(accounts.prefix(1))
        return activeAccounts
            .filter { states[$0.id]?.isConnected == true }
            .compactMap { account in
                effectiveRefreshInterval.nextRefreshDate(
                    lastSuccessfulUpdate: states[account.id]?.snapshot?.updatedAt,
                    lastRefreshAttempt: lastRefreshAttempts[account.id],
                    now: now
                )
            }
            .min()
    }
}
