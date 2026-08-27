import QuotaGlanceCore
import SwiftUI

struct WatchDashboardView: View {
    let store: WatchDashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    QuotaGlanceBrandIcon(size: 18)
                    Text("QuotaGlance")
                        .font(.headline)
                        .foregroundStyle(QuotaGlanceTheme.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasAccounts {
                    ForEach(AIProvider.allCases) { provider in
                        let accounts = store.accountPresentations(for: provider)
                        if !accounts.isEmpty {
                            WatchProviderSection(
                                provider: provider,
                                accounts: accounts,
                                showsWeekly: store.envelope?.accessLevel.hasProFeatures ?? false
                            )
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No usage yet",
                        systemImage: "iphone.and.arrow.forward",
                        description: Text("Open QuotaGlance on iPhone to connect and refresh.")
                    )
                }

                if let updatedAt = store.latestUpdatedAt {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            if UsageFormatting.isStale(updatedAt: updatedAt) {
                                Image(systemName: "clock.badge.exclamationmark")
                            }
                            Text("Last updated")
                        }
                        Text(UsageFormatting.compactDateTime(updatedAt))
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(QuotaGlanceTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                }

                Button {
                    Task { await store.refresh() }
                } label: {
                    HStack(spacing: 6) {
                        if store.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(store.isRefreshing ? String(localized: "Refreshing…") : String(localized: "Refresh data"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
                .tint(QuotaGlanceTheme.brandAccent)
                .disabled(store.isRefreshing)
                .frame(maxWidth: .infinity, alignment: .center)

                if store.refreshFailed {
                    Label(
                        "Unable to refresh. Cached data is preserved.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(QuotaGlanceTheme.attention)
                }
            }
            .padding(.horizontal, 2)
        }
        .background(QuotaGlanceTheme.appBackground.ignoresSafeArea())
    }

    private var hasAccounts: Bool {
        AIProvider.allCases.contains { !store.accountPresentations(for: $0).isEmpty }
    }
}

private struct WatchProviderSection: View {
    let provider: AIProvider
    let accounts: [AccountUsagePresentation]
    let showsWeekly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(
                provider.displayName.uppercased(),
                systemImage: provider == .codex ? "terminal" : "sparkles"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(provider.accent)

            ForEach(accounts) { account in
                WatchAccountCard(account: account, showsWeekly: showsWeekly)
            }
        }
    }
}

private struct WatchAccountCard: View {
    let account: AccountUsagePresentation
    let showsWeekly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(account.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            quotaRow(label: "5H", window: account.snapshot?.session)
            if showsWeekly {
                quotaRow(label: String(localized: "Weekly"), window: account.snapshot?.weekly)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .quotaCardSurface(cornerRadius: 10)
        .accessibilityElement(children: .combine)
    }

    private func quotaRow(label: String, window: UsageWindow?) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(window.map { "\($0.roundedRemainingPercentage)%" } ?? "—")
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(window == nil ? QuotaGlanceTheme.tertiaryText : account.provider.accent)
            Text(window?.resetAt.map { UsageFormatting.compactDateTime($0) } ?? "—")
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption2)
        .foregroundStyle(QuotaGlanceTheme.secondaryText)
    }
}

#Preview("All accounts") {
    WatchDashboardView(store: WatchPreview.store())
}

@MainActor
enum WatchPreview {
    private static let codexID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let claudeID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    static func store(accessLevel: AccessLevel = .pro) -> WatchDashboardStore {
        let store = WatchDashboardStore()
        let updatedAt = Date()
        let allAccounts = [
            AccountDisplayMetadata(id: codexID, provider: .codex, ordinal: 1, displayName: "Studio"),
            AccountDisplayMetadata(id: claudeID, provider: .claude, ordinal: 1, displayName: "Research"),
        ]
        let allSnapshots = [
            preview(.codex, accountIdentifier: codexID, remaining: 72, updatedAt: updatedAt),
            preview(.claude, accountIdentifier: claudeID, remaining: 48, updatedAt: updatedAt),
        ]
        let isPro = accessLevel.hasProFeatures
        let accounts = isPro ? allAccounts : Array(allAccounts.prefix(1))
        let snapshots = isPro ? allSnapshots : Array(allSnapshots.prefix(1))
        store.apply(SnapshotEnvelope(
            snapshots: snapshots,
            accounts: accounts,
            watchAccountIdentifiers: accounts.map(\.id),
            accessLevel: accessLevel
        ))
        return store
    }

    private static func preview(
        _ provider: AIProvider,
        accountIdentifier: UUID,
        remaining: Double,
        updatedAt: Date
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            accountIdentifier: accountIdentifier,
            session: UsageWindow(usedPercentage: 100 - remaining, resetAt: Date().addingTimeInterval(6_000)),
            weekly: UsageWindow(usedPercentage: provider == .codex ? 59 : 37, resetAt: Date().addingTimeInterval(400_000)),
            updatedAt: updatedAt
        )
    }
}
