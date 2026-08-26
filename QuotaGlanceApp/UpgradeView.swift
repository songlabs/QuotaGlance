import StoreKit
import SwiftUI

struct UpgradeView: View {
    @Bindable var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var isWorking = false
    @State private var resultMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(statusTitle, systemImage: "sparkles").font(.headline)
                    Text(statusDetail).foregroundStyle(QuotaGlanceTheme.secondaryText)
                }

                if store.purchaseManager.canStartTrial {
                    Section(AppLocalization.string("7-Day Pro Trial", locale: locale)) {
                        disclosure("Trial lasts 7 days")
                        disclosure("All Pro features are available during the trial")
                        disclosure("After the trial you will return to Free")
                        disclosure("No automatic charge")
                        disclosure("No automatic Pro purchase")
                        disclosure("No subscription")
                        disclosure("Free remains available after the trial")
                        disclosure("Pro is a one-time purchase")
                        LabeledContent(
                            AppLocalization.string("Full unlock price", locale: locale),
                            value: store.purchaseManager.lifetimeProduct?.displayPrice ?? "—"
                        )
                        Button {
                            Task { await purchaseTrial() }
                        } label: {
                            workingLabel(AppLocalization.string("Start 7-Day Free Trial", locale: locale))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || store.purchaseManager.trialProduct == nil)
                    }
                }

                Section(AppLocalization.string("Free and Pro", locale: locale)) {
                    feature("Free", "One account with 5H usage on iPhone and Apple Watch")
                    feature("Free keeps one account, 5H, basic iPhone viewing, and Free Watch 5H")
                    feature("Pro", "Multiple accounts, Weekly, widgets, and full Apple Watch features")
                    feature("Trial expiry removes Weekly, multiple accounts, full widgets, and advanced Apple Watch displays")
                }

                if store.accessLevel != .pro {
                    Section {
                        LabeledContent(
                            AppLocalization.string("Buy Once", locale: locale),
                            value: store.purchaseManager.lifetimeProduct?.displayPrice ?? "—"
                        )
                        Text(AppLocalization.string("Lifetime Unlock", locale: locale))
                            .foregroundStyle(QuotaGlanceTheme.secondaryText)
                        Button {
                            Task { await purchaseLifetime() }
                        } label: {
                            workingLabel(AppLocalization.string("Buy Pro", locale: locale))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || store.purchaseManager.lifetimeProduct == nil)
                    }
                }

                Section {
                    Button(AppLocalization.string("Restore Purchases", locale: locale)) {
                        Task { await restore() }
                    }
                    .disabled(isWorking)
                }
            }
            .navigationTitle(AppLocalization.string("Upgrade to Pro", locale: locale))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Done", locale: locale)) { dismiss() }
                }
            }
            .alert(resultMessage ?? "", isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )) {
                Button(AppLocalization.string("OK", locale: locale)) { resultMessage = nil }
            }
        }
        .preferredColorScheme(.dark)
        .tint(QuotaGlanceTheme.brandAccent)
    }

    private var statusTitle: String {
        switch store.accessLevel {
        case .free:
            AppLocalization.string(store.purchaseManager.canStartTrial ? "Trial Not Started" : "Trial Expired", locale: locale)
        case .trial: AppLocalization.string("Pro Trial", locale: locale)
        case .pro: AppLocalization.string("Pro", locale: locale)
        }
    }

    private var statusDetail: String {
        switch store.accessLevel {
        case .free:
            AppLocalization.string(store.purchaseManager.canStartTrial ? "Start the trial when you are ready" : "After the trial you will return to Free", locale: locale)
        case .trial:
            guard let end = store.purchaseManager.trialEndsAt else { return "" }
            return AppLocalization.string("Trial Ends", locale: locale) + ": " + end.formatted(date: .abbreviated, time: .shortened)
        case .pro: return AppLocalization.string("Lifetime Unlock", locale: locale)
        }
    }

    private func disclosure(_ key: String) -> some View {
        Label(AppLocalization.string(key, locale: locale), systemImage: "checkmark")
    }

    private func feature(_ title: String, _ detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(AppLocalization.string(title, locale: locale)).font(.headline)
            if let detail {
                Text(AppLocalization.string(detail, locale: locale)).foregroundStyle(QuotaGlanceTheme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func workingLabel(_ title: String) -> some View {
        HStack { if isWorking { ProgressView() }; Text(title); Spacer() }
    }

    private func purchaseTrial() async {
        let previous = store.accessLevel
        isWorking = true
        let succeeded = await store.purchaseManager.purchaseTrial()
        await store.refreshAccess(previousAccessLevel: previous)
        isWorking = false
        resultMessage = AppLocalization.string(succeeded ? "Trial Started" : "Purchase Failed", locale: locale)
    }

    private func purchaseLifetime() async {
        let previous = store.accessLevel
        isWorking = true
        let succeeded = await store.purchaseManager.purchaseLifetime()
        await store.refreshAccess(previousAccessLevel: previous)
        isWorking = false
        resultMessage = AppLocalization.string(succeeded ? "Purchase Successful" : "Purchase Failed", locale: locale)
    }

    private func restore() async {
        let previous = store.accessLevel
        isWorking = true
        await store.purchaseManager.restorePurchases()
        await store.refreshAccess(previousAccessLevel: previous)
        isWorking = false
        resultMessage = AppLocalization.string("Restore Completed", locale: locale)
    }
}
