import Foundation
import QuotaGlanceCore

@MainActor
enum AppEnvironment {
    static func makeDashboardStore() -> DashboardStore {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshot-mode") {
            return PreviewFactory.dashboard(states: PreviewFactory.normalStates)
        }
#endif
        let credentials = KeychainCredentialStore()
        let oauthSession = LoopbackOAuthSession()
        let providers: [AIProvider: any UsageProvider] = [
            .codex: CodexUsageProvider(credentials: credentials, oauthSession: oauthSession),
            .claude: ClaudeUsageProvider(credentials: credentials, oauthSession: oauthSession),
        ]
        return DashboardStore(
            providers: providers,
            credentials: credentials,
            registry: AccountRegistry(),
            cache: AppGroupSnapshotCache(),
            watchSync: PhoneWatchSync(),
            purchaseManager: PurchaseManager()
        )
    }
}
