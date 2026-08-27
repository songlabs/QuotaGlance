import SwiftUI

@main
@MainActor
struct QuotaGlanceApp: App {
    @State private var store: DashboardStore
    private let screenshotConfiguration: ScreenshotConfiguration?

    init() {
        let configuration = ScreenshotConfiguration.current
        screenshotConfiguration = configuration
        _store = State(initialValue: AppEnvironment.makeDashboardStore(
            screenshotConfiguration: configuration
        ))
    }

    var body: some Scene {
        WindowGroup {
            screenshotRoot
                .preferredColorScheme(.dark)
                .environment(\.locale, store.appLanguage.locale)
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
