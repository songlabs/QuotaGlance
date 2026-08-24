import SwiftUI

@main
@MainActor
struct QuotaGlanceApp: App {
    @State private var store: DashboardStore

    init() {
        _store = State(initialValue: AppEnvironment.makeDashboardStore())
    }

    var body: some Scene {
        WindowGroup {
            DashboardView(store: store)
                .preferredColorScheme(.dark)
                .environment(\.locale, store.appLanguage.locale)
        }
    }
}
