import Foundation
import QuotaGlanceCore

@MainActor
enum AppEnvironment {
    static func makeDashboardStore() -> DashboardStore {
        let credentials = KeychainCredentialStore()
        let oauthSession = LoopbackOAuthSession()
        let providers: [AIProvider: any UsageProvider] = [
            .codex: CodexUsageProvider(credentials: credentials, oauthSession: oauthSession),
            .claude: ClaudeUsageProvider(credentials: credentials, oauthSession: oauthSession),
        ]
        return DashboardStore(
            providers: providers,
            cache: AppGroupSnapshotCache(),
            watchSync: PhoneWatchSync()
        )
    }
}
