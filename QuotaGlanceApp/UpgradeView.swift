import StoreKit
import SwiftUI

struct UpgradeView: View {
    @Bindable var store: DashboardStore
    let initialScrollTarget: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var isWorking = false
    @State private var resultMessage: String?

    init(store: DashboardStore, initialScrollTarget: String? = nil) {
        self.store = store
        self.initialScrollTarget = initialScrollTarget
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                            value: store.purchaseManager.lifetimeDisplayPrice ?? "—"
                        )
                        Button {
                            Task { await purchaseTrial() }
                        } label: {
                            workingLabel(AppLocalization.string("Start 7-Day Free Trial", locale: locale))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || store.isAppReviewDemoEnabled || !store.purchaseManager.canPresentTrialPurchase)
                    }
                    .id("trial")
                }

                Section(AppLocalization.string("Free and Pro", locale: locale)) {
                    featureComparisonTable
                }
                .listRowBackground(QuotaGlanceTheme.cardBackground)
                .id("comparison")

                if store.accessLevel != .pro {
                    Section {
                        LabeledContent(
                            AppLocalization.string("Buy Once", locale: locale),
                            value: store.purchaseManager.lifetimeDisplayPrice ?? "—"
                        )
                        Text(AppLocalization.string("Lifetime Unlock", locale: locale))
                            .foregroundStyle(QuotaGlanceTheme.secondaryText)
                        Button {
                            Task { await purchaseLifetime() }
                        } label: {
                            workingLabel(AppLocalization.string("Buy Pro", locale: locale))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || store.isAppReviewDemoEnabled || !store.purchaseManager.canPresentLifetimePurchase)
                    }
                    .id("purchase")
                }

                Section {
                    Button(AppLocalization.string("Restore Purchases", locale: locale)) {
                        Task { await restore() }
                    }
                    .disabled(isWorking || store.isAppReviewDemoEnabled)
                }
                .id("restore")
                }
                .onAppear {
                    guard let initialScrollTarget else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(initialScrollTarget, anchor: .top)
                    }
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
            return AppLocalization.string(store.purchaseManager.canStartTrial ? "Start the trial when you are ready" : "After the trial you will return to Free", locale: locale)
        case .trial:
            guard let end = store.purchaseManager.trialEndsAt else { return "" }
            return AppLocalization.string("Trial Ends", locale: locale) + ": " + end.formatted(date: .abbreviated, time: .shortened)
        case .pro: return AppLocalization.string("Lifetime Unlock", locale: locale)
        }
    }

    private func disclosure(_ key: String) -> some View {
        Label(AppLocalization.string(key, locale: locale), systemImage: "checkmark")
    }

    private var featureComparisonTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                comparisonTitle("Feature", isHeader: true)
                comparisonHeader("Free plan")
                comparisonHeader("Pro")
            }
            .padding(.bottom, 6)

            Divider()
            comparisonRow("iPhone 5H", free: .included, pro: .included)
            Divider()
            comparisonRow("iPhone Weekly", free: .unavailable, pro: .included)
            Divider()
            comparisonRow("iPhone multiple accounts", free: .unavailable, pro: .included)
            Divider()
            comparisonRow("iPhone Widget", free: .unavailable, pro: .included)
            Divider()
            comparisonRow("Apple Watch 5H", free: .included, pro: .included)
            Divider()
            comparisonRow("Apple Watch Weekly", free: .unavailable, pro: .included)
            Divider()
            comparisonRow("Apple Watch multiple accounts", free: .unavailable, pro: .included)
            Divider()
            comparisonRow(
                "Automatic data refresh",
                free: .text("4 hours fixed"),
                pro: .text("Customizable")
            )
        }
    }

    private func comparisonRow(
        _ title: String,
        free: FeatureAvailability,
        pro: FeatureAvailability
    ) -> some View {
        HStack(spacing: 8) {
            comparisonTitle(title)
            comparisonValue(free)
            comparisonValue(pro)
        }
        .padding(.vertical, 7)
    }

    private func comparisonTitle(_ key: String, isHeader: Bool = false) -> some View {
        Text(AppLocalization.string(key, locale: locale))
            .font(isHeader ? .caption.weight(.semibold) : .subheadline)
            .foregroundStyle(isHeader ? QuotaGlanceTheme.secondaryText : QuotaGlanceTheme.primaryText)
            .lineLimit(3)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonHeader(_ key: String) -> some View {
        Text(AppLocalization.string(key, locale: locale))
            .font(.caption.weight(.semibold))
            .foregroundStyle(QuotaGlanceTheme.secondaryText)
            .frame(width: 64)
    }

    @ViewBuilder
    private func comparisonValue(_ availability: FeatureAvailability) -> some View {
        Group {
            switch availability {
            case .included:
                Image(systemName: "checkmark")
                    .foregroundStyle(QuotaGlanceTheme.brandAccent)
                    .accessibilityLabel(AppLocalization.string("Included", locale: locale))
            case .unavailable:
                Text("—")
                    .foregroundStyle(QuotaGlanceTheme.tertiaryText)
                    .accessibilityLabel(AppLocalization.string("Not included", locale: locale))
            case let .text(key):
                Text(AppLocalization.string(key, locale: locale))
                    .foregroundStyle(QuotaGlanceTheme.primaryText)
            }
        }
        .font(.caption.weight(.semibold))
        .lineLimit(2)
        .minimumScaleFactor(0.75)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 64)
        .frame(minHeight: 28)
    }

    private enum FeatureAvailability {
        case included
        case unavailable
        case text(String)
    }

    @ViewBuilder
    private func workingLabel(_ title: String) -> some View {
        HStack { if isWorking { ProgressView() }; Text(title); Spacer() }
    }

    private func purchaseTrial() async {
        guard !store.isAppReviewDemoEnabled else { return }
        let previous = store.accessLevel
        isWorking = true
        let succeeded = await store.purchaseManager.purchaseTrial()
        await store.refreshAccess(previousAccessLevel: previous)
        isWorking = false
        resultMessage = AppLocalization.string(succeeded ? "Trial Started" : "Purchase Failed", locale: locale)
    }

    private func purchaseLifetime() async {
        guard !store.isAppReviewDemoEnabled else { return }
        let previous = store.accessLevel
        isWorking = true
        let succeeded = await store.purchaseManager.purchaseLifetime()
        await store.refreshAccess(previousAccessLevel: previous)
        isWorking = false
        resultMessage = AppLocalization.string(succeeded ? "Purchase Successful" : "Purchase Failed", locale: locale)
    }

    private func restore() async {
        guard !store.isAppReviewDemoEnabled else { return }
        let previous = store.accessLevel
        isWorking = true
        let succeeded = await store.purchaseManager.restorePurchases()
        await store.refreshAccess(previousAccessLevel: previous)
        isWorking = false
        resultMessage = AppLocalization.string(
            restoreFeedbackLocalizationKey(succeeded: succeeded),
            locale: locale
        )
    }
}
