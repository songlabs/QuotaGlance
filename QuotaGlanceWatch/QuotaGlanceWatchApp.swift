import QuotaGlanceCore
import SwiftUI

@main
@MainActor
struct QuotaGlanceWatchApp: App {
    @State private var store: WatchDashboardStore = {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshot-mode") {
            let arguments = ProcessInfo.processInfo.arguments
            let access: AccessLevel
            if let index = arguments.firstIndex(of: "--screenshot-access"),
               arguments.indices.contains(index + 1),
               arguments[index + 1] == "free" {
                access = .free
            } else {
                access = .pro
            }
            return WatchPreview.store(accessLevel: access)
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
