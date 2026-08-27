import SwiftUI

@main
@MainActor
struct QuotaGlanceApp: App {
    @State private var store: DashboardStore
    @Environment(\.scenePhase) private var scenePhase
    private let screenshotConfiguration: ScreenshotConfiguration?
    private let backgroundRefreshScheduler: BackgroundRefreshScheduler

    init() {
        let configuration = ScreenshotConfiguration.current
        let store = AppEnvironment.makeDashboardStore(
            screenshotConfiguration: configuration
        )
        screenshotConfiguration = configuration
        _store = State(initialValue: store)
        backgroundRefreshScheduler = BackgroundRefreshScheduler(store: store)
    }

    var body: some Scene {
        WindowGroup {
            screenshotRoot
                .id(screenshotConfiguration?.identity ?? "production")
                .preferredColorScheme(.dark)
                .environment(\.locale, store.appLanguage.locale)
                .onChange(of: scenePhase, initial: true) { _, newValue in
                    switch newValue {
                    case .active:
                        backgroundRefreshScheduler.appEnteredForeground()
                    case .background:
                        backgroundRefreshScheduler.appEnteredBackground()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }

    @ViewBuilder
    private var screenshotRoot: some View {
        switch screenshotConfiguration?.screen {
        case .settings:
            SettingsView(
                store: store,
                initialScrollTarget: screenshotConfiguration?.position
            )
        case .upgrade:
            UpgradeView(
                store: store,
                initialScrollTarget: screenshotConfiguration?.position
            )
        case .dashboard:
            DashboardView(store: store, runsStartupTasks: false)
        case nil:
            DashboardView(store: store)
        }
    }
}
