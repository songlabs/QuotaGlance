import Foundation
import Observation
import QuotaGlanceCore
import WidgetKit

struct ProviderPresentation: Equatable {
    let provider: AIProvider
    var isConnected: Bool
    var snapshot: UsageSnapshot?
    var isRefreshing: Bool
    var errorMessage: String?
}

@Observable
@MainActor
final class DashboardStore {
    private let providers: [AIProvider: any UsageProvider]
    private let cache: any SnapshotCaching
    private let watchSync: any PhoneWatchSynchronizing
    private let cacheLifetime: TimeInterval = 5 * 60

    var states: [AIProvider: ProviderPresentation]
    var isShowingSettings = false

    init(
        providers: [AIProvider: any UsageProvider],
        cache: any SnapshotCaching,
        watchSync: any PhoneWatchSynchronizing
    ) {
        self.providers = providers
        self.cache = cache
        self.watchSync = watchSync
        let cached = cache.load()
        states = Dictionary(uniqueKeysWithValues: AIProvider.allCases.map { provider in
            (provider, ProviderPresentation(
                provider: provider,
                isConnected: providers[provider]?.isConnected ?? false,
                snapshot: cached?.snapshot(for: provider),
                isRefreshing: false,
                errorMessage: nil
            ))
        })
    }

    var defaultProvider: AIProvider {
        get { (cache as? AppGroupSnapshotCache)?.defaultProvider ?? .codex }
        set {
            (cache as? AppGroupSnapshotCache)?.defaultProvider = newValue
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func refreshAll(force: Bool) async {
        for provider in AIProvider.allCases where states[provider]?.isConnected == true {
            if !force,
               let updatedAt = states[provider]?.snapshot?.updatedAt,
               Date().timeIntervalSince(updatedAt) <= cacheLifetime {
                continue
            }
            await refresh(provider)
        }
    }

    func refresh(_ provider: AIProvider) async {
        guard let usageProvider = providers[provider], states[provider]?.isConnected == true else { return }
        states[provider]?.isRefreshing = true
        states[provider]?.errorMessage = nil
        defer { states[provider]?.isRefreshing = false }

        do {
            let snapshot = try await usageProvider.refreshUsage()
            states[provider]?.snapshot = snapshot
            states[provider]?.errorMessage = nil
            publishSnapshots()
        } catch {
            if requiresReconnect(error) {
                states[provider]?.isConnected = false
            }
            states[provider]?.errorMessage = displayMessage(for: error)
        }
    }

    func connect(_ provider: AIProvider) async {
        guard let usageProvider = providers[provider] else { return }
        states[provider]?.isRefreshing = true
        states[provider]?.errorMessage = nil
        defer { states[provider]?.isRefreshing = false }

        do {
            try await usageProvider.connect()
            states[provider]?.isConnected = true
            let snapshot = try await usageProvider.refreshUsage()
            states[provider]?.snapshot = snapshot
            publishSnapshots()
        } catch {
            states[provider]?.isConnected = requiresReconnect(error) ? false : usageProvider.isConnected
            states[provider]?.errorMessage = displayMessage(for: error)
        }
    }

    func disconnect(_ provider: AIProvider) async {
        guard let usageProvider = providers[provider] else { return }
        do {
            try await usageProvider.disconnect()
            states[provider]?.isConnected = false
            states[provider]?.snapshot = nil
            states[provider]?.errorMessage = nil
            try cache.remove(provider)
            publishSnapshots()
        } catch {
            states[provider]?.errorMessage = displayMessage(for: error)
        }
    }

    func loadPreview(_ previews: [ProviderPresentation]) {
        states = Dictionary(uniqueKeysWithValues: previews.map { ($0.provider, $0) })
    }

    private func publishSnapshots() {
        let envelope = SnapshotEnvelope(snapshots: AIProvider.allCases.compactMap { states[$0]?.snapshot })
        try? cache.save(envelope)
        watchSync.send(envelope)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func displayMessage(for error: Error) -> String {
        if let error = error as? UsageProviderError {
            switch error {
            case .network:
                return String(localized: "Unable to refresh. Check your connection.")
            case .tokenExpired, .noAccount:
                return String(localized: "Session expired. Connect again.")
            case .schemaChanged:
                return String(localized: "Provider response changed. Cached data is preserved.")
            case let .rejected(statusCode) where statusCode == 429:
                return String(localized: "Provider rate-limited refresh. Try again later.")
            default:
                return String(localized: "Something went wrong. Try again.")
            }
        }
        return String(localized: "Unable to refresh. Cached data is preserved.")
    }

    private func requiresReconnect(_ error: Error) -> Bool {
        guard let error = error as? UsageProviderError else { return false }
        return error == .tokenExpired || error == .noAccount
    }
}
