import SwiftUI

@main
@MainActor
struct QuotaGlanceWatchApp: App {
    @State private var store = WatchDashboardStore()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView(store: store)
        }
    }
}
