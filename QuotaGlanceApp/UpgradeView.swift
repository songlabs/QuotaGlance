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
                    VStack(alignment: .leading, spacing: 8) {
                        Label(AppLocalization.string("7-Day Free Trial", locale: locale), systemImage: "sparkles")
                            .font(.headline)
                        Text(trialStatus)
                            .foregroundStyle(QuotaGlanceTheme.secondaryText)
                    }
                }

                Section(AppLocalization.string("Free and Pro", locale: locale)) {
                    feature("Free", "One account with 5H usage on iPhone and Apple Watch")
                    feature("Pro", "Multiple accounts, Weekly, widgets, and full Apple Watch features")
                }

                Section {
                    LabeledContent(
                        AppLocalization.string("Buy Once", locale: locale),
                        value: store.purchaseManager.product?.displayPrice ?? "—"
                    )
                    Text(AppLocalization.string("Lifetime Unlock", locale: locale))
                        .foregroundStyle(QuotaGlanceTheme.secondaryText)

                    Button {
                        Task { await purchase() }
                    } label: {
                        workingLabel(AppLocalization.string("Purchase", locale: locale))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || store.purchaseManager.product == nil || store.accessLevel == .pro)

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
                Button("OK") { resultMessage = nil }
            }
        }
        .preferredColorScheme(.dark)
        .tint(QuotaGlanceTheme.brandAccent)
    }

    private var trialStatus: String {
        switch store.accessLevel {
        case .trial:
            let days = max(1, Int(ceil(store.purchaseManager.trialTimeRemaining / 86_400)))
            return AppLocalization.string("trial.days.remaining", defaultValue: "Trial Ends in %lld days", locale: locale, arguments: [days])
        case .free: return AppLocalization.string("Trial Ended", locale: locale)
        case .pro: return AppLocalization.string("Already Purchased", locale: locale)
        }
    }

    private func feature(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(AppLocalization.string(title, locale: locale)).font(.headline)
            Text(AppLocalization.string(detail, locale: locale)).foregroundStyle(QuotaGlanceTheme.secondaryText)
        }
    }

    @ViewBuilder
    private func workingLabel(_ title: String) -> some View {
        HStack { if isWorking { ProgressView() }; Text(title); Spacer() }
    }

    private func purchase() async {
        isWorking = true
        let succeeded = await store.purchaseManager.purchase()
        await store.refreshAccess()
        isWorking = false
        resultMessage = AppLocalization.string(succeeded ? "Purchase Successful" : "Purchase Failed", locale: locale)
    }

    private func restore() async {
        isWorking = true
        await store.purchaseManager.restorePurchases()
        await store.refreshAccess()
        isWorking = false
        resultMessage = AppLocalization.string(
            store.accessLevel == .pro ? "Already Purchased" : "Purchase Failed",
            locale: locale
        )
    }
}
