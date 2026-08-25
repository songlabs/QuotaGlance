import QuotaGlanceCore
import SwiftUI

struct WatchDashboardView: View {
    let store: WatchDashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    QuotaGlanceBrandIcon(size: 18)
                    Text("QuotaGlance")
                        .font(.headline)
                        .foregroundStyle(QuotaGlanceTheme.primaryText)
                }
                    .frame(maxWidth: .infinity, alignment: .leading)

                if store.snapshots.isEmpty {
                    ContentUnavailableView(
                        "No usage yet",
                        systemImage: "iphone.and.arrow.forward",
                        description: Text("Open QuotaGlance on iPhone to connect and refresh.")
                    )
                } else {
                    ForEach(AIProvider.allCases) { provider in
                        if let snapshot = store.snapshots[provider] {
                            WatchProviderCard(snapshot: snapshot, displayLimit: store.displayLimit)
                        }
                    }
                }

                if let updatedAt = store.latestUpdatedAt {
                    HStack(spacing: 4) {
                        if UsageFormatting.isStale(updatedAt: updatedAt) {
                            Image(systemName: "clock.badge.exclamationmark")
                        }
                        Text(UsageFormatting.updatedText(updatedAt: updatedAt))
                    }
                    .font(.caption2)
                    .foregroundStyle(QuotaGlanceTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 2)
        }
        .background(QuotaGlanceTheme.appBackground.ignoresSafeArea())
    }
}
private struct WatchProviderCard: View {
    let snapshot: UsageSnapshot
    let displayLimit: QuotaDisplayLimit

    private var window: UsageWindow? { displayLimit.window(in: snapshot) }

    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.provider.displayName.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer()
                Text(window.map { "\($0.roundedRemainingPercentage)%" } ?? "—")
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(limitColor)
            }

            HStack(spacing: 6) {
                Text(limitLabel)
                Spacer()
                Text(resetText(window?.resetAt))
            }
            .font(.caption2)
            .foregroundStyle(QuotaGlanceTheme.secondaryText)

        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .quotaCardSurface(cornerRadius: 10)
        .accessibilityElement(children: .combine)
    }

    private var accent: Color {
        snapshot.provider.accent
    }

    private var limitColor: Color {
        color(window)
    }

    private var limitLabel: String {
        switch displayLimit {
        case .fiveHour: String(localized: "5 hours")
        case .weekly: String(localized: "Weekly")
        }
    }

    private func color(_ window: UsageWindow?) -> Color {
        window == nil ? QuotaGlanceTheme.tertiaryText : accent
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return String(localized: "Reset —") }
        let time = date.formatted(date: .omitted, time: .shortened)
        return String(localized: "reset.time", defaultValue: "Reset \(time)")
    }
}

#Preview("Both normal") {
    WatchDashboardView(store: WatchPreview.store(codex: 72, claude: 48))
}

#Preview("Codex only") {
    WatchDashboardView(store: WatchPreview.store(codex: 72, claude: nil))
}

#Preview("Claude only") {
    WatchDashboardView(store: WatchPreview.store(codex: nil, claude: 48))
}

#Preview("Low and stale") {
    WatchDashboardView(store: WatchPreview.store(codex: 11, claude: 18, stale: true))
}

@MainActor
private enum WatchPreview {
    static func store(codex: Double?, claude: Double?, stale: Bool = false) -> WatchDashboardStore {
        let store = WatchDashboardStore()
        let updatedAt = stale ? Date().addingTimeInterval(-3_600) : Date()
        let snapshots = [
            codex.map { preview(.codex, remaining: $0, updatedAt: updatedAt) },
            claude.map { preview(.claude, remaining: $0, updatedAt: updatedAt) },
        ].compactMap { $0 }
        store.apply(SnapshotEnvelope(snapshots: snapshots))
        return store
    }

    private static func preview(_ provider: AIProvider, remaining: Double, updatedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            session: UsageWindow(usedPercentage: 100 - remaining, resetAt: Date().addingTimeInterval(6_000)),
            weekly: UsageWindow(usedPercentage: provider == .codex ? 59 : 37, resetAt: Date().addingTimeInterval(400_000)),
            updatedAt: updatedAt
        )
    }
}
