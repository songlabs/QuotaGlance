import QuotaGlanceCore
import SwiftUI

struct WatchDashboardView: View {
    let store: WatchDashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                Text("QuotaGlance")
                    .font(.headline)
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
                            WatchProviderCard(snapshot: snapshot)
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
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
private struct WatchProviderCard: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.provider.displayName.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer()
                Text(snapshot.session.map { "\($0.roundedRemainingPercentage)%" } ?? "—")
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(sessionColor)
            }

            HStack(spacing: 6) {
                Text("5h")
                Spacer()
                Text(resetText(snapshot.session?.resetAt))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text("Weekly")
                ProgressView(value: snapshot.weekly?.remainingPercentage ?? 0, total: 100)
                    .tint(weeklyColor)
                Text(snapshot.weekly.map { "\($0.roundedRemainingPercentage)%" } ?? "—")
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
            }
            .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var accent: Color {
        snapshot.provider == .codex ? .green : .orange
    }

    private var sessionColor: Color {
        color(snapshot.session)
    }

    private var weeklyColor: Color {
        color(snapshot.weekly)
    }

    private func color(_ window: UsageWindow?) -> Color {
        guard let window else { return .secondary }
        switch window.level {
        case .normal: accent
        case .attention: .orange
        case .low: .red
        }
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return "Reset —" }
        return "Reset \(date.formatted(date: .omitted, time: .shortened))"
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
