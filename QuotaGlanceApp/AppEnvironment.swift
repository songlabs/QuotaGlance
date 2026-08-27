import Foundation
import QuotaGlanceCore

enum ScreenshotScreen: String {
    case dashboard
    case settings
    case upgrade
}

enum ScreenshotAccess: String {
    case free
    case trial
    case trialExpired = "trial-expired"
    case pro

    var accessLevel: AccessLevel {
        switch self {
        case .free, .trialExpired: .free
        case .trial: .trial
        case .pro: .pro
        }
    }
}

struct ScreenshotConfiguration {
    let screen: ScreenshotScreen
    let access: ScreenshotAccess
    let position: String?

    static var current: ScreenshotConfiguration? {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--screenshot-mode") else { return nil }
        let screen = value(after: "--screenshot-screen", in: arguments)
            .flatMap(ScreenshotScreen.init(rawValue:)) ?? .dashboard
        let access = value(after: "--screenshot-access", in: arguments)
            .flatMap(ScreenshotAccess.init(rawValue:)) ?? .pro
        return ScreenshotConfiguration(
            screen: screen,
            access: access,
            position: value(after: "--screenshot-position", in: arguments)
        )
#else
        return nil
#endif
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

@MainActor
enum AppEnvironment {
    static func makeDashboardStore(
        screenshotConfiguration: ScreenshotConfiguration? = ScreenshotConfiguration.current
    ) -> DashboardStore {
#if DEBUG
        if let screenshotConfiguration {
            return PreviewFactory.dashboard(
                states: PreviewFactory.normalStates,
                access: screenshotConfiguration.access
            )
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
