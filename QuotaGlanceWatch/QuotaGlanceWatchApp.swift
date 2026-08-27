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
            WatchDashboardView(
                store: store,
                initialScrollTarget: screenshotPosition
            )
            .id(screenshotIdentity)
        }
    }

    private var screenshotPosition: String? {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--screenshot-mode"),
              let index = arguments.firstIndex(of: "--screenshot-position"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
#else
        return nil
#endif
    }

    private var screenshotIdentity: String {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--screenshot-mode") else { return "production" }
        let access: String
        if let index = arguments.firstIndex(of: "--screenshot-access"),
           arguments.indices.contains(index + 1) {
            access = arguments[index + 1]
        } else {
            access = "pro"
        }
        return "\(access)-\(screenshotPosition ?? "top")"
#else
        return "production"
#endif
    }
}
