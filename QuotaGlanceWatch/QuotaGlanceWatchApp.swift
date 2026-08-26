import SwiftUI

@main
@MainActor
struct QuotaGlanceWatchApp: App {
    @State private var store: WatchDashboardStore = {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshot-mode") {
            return WatchPreview.store()
        }
#endif
        return WatchDashboardStore()
    }()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView(store: store)
        }
    }
}
