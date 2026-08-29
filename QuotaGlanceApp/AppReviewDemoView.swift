import QuotaGlanceCore
import SwiftUI

enum AppReviewDemoUnlock {
    static let requiredTapCount = 7

    static func nextTapCount(after currentCount: Int) -> Int {
        min(currentCount + 1, requiredTapCount)
    }

    static func shouldUnlock(afterTapCount tapCount: Int) -> Bool {
        tapCount >= requiredTapCount
    }
}

struct AppReviewDemoView: View {
    @Bindable var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        AppLocalization.string("Demo Mode", locale: locale),
                        isOn: Binding(
                            get: { store.isAppReviewDemoEnabled },
                            set: { isEnabled in
                                if isEnabled {
                                    store.enableAppReviewDemo()
                                } else {
                                    store.disableAppReviewDemo()
                                }
                            }
                        )
                    )
                    .disabled(!store.isAppReviewDemoEnabled && !store.canEnableAppReviewDemo)

                    if !store.isAppReviewDemoEnabled && !store.canEnableAppReviewDemo {
                        Label(
                            AppLocalization.string(
                                "Wait for QuotaGlance to finish loading before enabling Demo Mode.",
                                locale: locale
                            ),
                            systemImage: "clock"
                        )
                        .foregroundStyle(QuotaGlanceTheme.secondaryText)
                    }

                    if store.isAppReviewDemoEnabled {
                        Label(
                            AppLocalization.string("Demo Mode is active", locale: locale),
                            systemImage: "checkmark.seal.fill"
                        )
                        .foregroundStyle(QuotaGlanceTheme.brandAccent)
                    }
                } footer: {
                    Text(AppLocalization.string(
                        "Demo Mode uses local sample data and does not access provider APIs, OAuth credentials, or StoreKit purchases.",
                        locale: locale
                    ))
                }

                Section(AppLocalization.string("Demo Access", locale: locale)) {
                    Picker(
                        AppLocalization.string("Demo Access", locale: locale),
                        selection: Binding(
                            get: { store.appReviewDemoAccessLevel },
                            set: { store.setAppReviewDemoAccessLevel($0) }
                        )
                    ) {
                        ForEach([AccessLevel.free, .trial, .pro], id: \.self) { accessLevel in
                            Text(accessTitle(accessLevel)).tag(accessLevel)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!store.isAppReviewDemoEnabled)
                } footer: {
                    Text(AppLocalization.string(
                        "Your real accounts, credentials, purchases, and settings are not changed.",
                        locale: locale
                    ))
                }

                Section {
                    Text(AppLocalization.string(
                        "The demo turns off when QuotaGlance is relaunched.",
                        locale: locale
                    ))
                    .foregroundStyle(QuotaGlanceTheme.secondaryText)
                }
            }
            .navigationTitle(AppLocalization.string("App Review Demo", locale: locale))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Done", locale: locale)) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(QuotaGlanceTheme.brandAccent)
    }

    private func accessTitle(_ accessLevel: AccessLevel) -> String {
        switch accessLevel {
        case .free: AppLocalization.string("Free", locale: locale)
        case .trial: AppLocalization.string("Trial", locale: locale)
        case .pro: AppLocalization.string("Pro", locale: locale)
        }
    }
}
