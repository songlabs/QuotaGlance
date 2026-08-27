import QuotaGlanceCore
import SwiftUI
import WidgetKit

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let envelope: SnapshotEnvelope?
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), envelope: ComplicationPreview.dualEnvelope)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        let envelope = SharedWatchSnapshotCache().load() ?? (context.isPreview ? ComplicationPreview.dualEnvelope : nil)
        completion(ComplicationEntry(date: Date(), envelope: envelope))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let envelope = SharedWatchSnapshotCache().load()
        let refreshInterval: TimeInterval = envelope == nil ? 60 : 15 * 60
        completion(Timeline(
            entries: [ComplicationEntry(date: Date(), envelope: envelope)],
            policy: .after(Date().addingTimeInterval(refreshInterval))
        ))
    }
}

struct QuotaGlanceComplication: Widget {
    let kind = "QuotaGlanceComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("QuotaGlance")
        .description("Codex and Claude remaining usage.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            Text(inlineText)
        default:
            Text("QuotaGlance")
        }
    }

    private var selectedAccounts: [AccountUsagePresentation] {
        entry.envelope?.watchAccountPresentations(at: entry.date) ?? []
    }

    private var hasProFeatures: Bool { entry.envelope?.hasProFeatures(at: entry.date) ?? false }

    private var circular: some View {
        let account = selectedAccounts.first
        let displayLimit = entry.envelope?.effectiveDisplayLimit(at: entry.date) ?? .fiveHour
        let window = account?.snapshot.flatMap { displayLimit.window(in: $0) }
        let remaining = window?.remainingPercentage
        return Gauge(value: remaining ?? 0, in: 0...100) {
            QuotaGlanceBrandIcon(size: 10)
                .widgetAccentable()
        } currentValueLabel: {
            Text(remaining.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.system(.caption, design: .rounded).bold())
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(account?.provider.accent ?? QuotaGlanceTheme.brandAccent)
        .accessibilityLabel(limitAccessibilityLabel(displayLimit))
        .accessibilityValue(accessibilityValue(account?.snapshot))
    }

    @ViewBuilder
    private var rectangular: some View {
        if selectedAccounts.count == 1, let account = selectedAccounts.first {
            singleAccountLayout(account)
        } else if selectedAccounts.count >= 2 {
            dualAccountLayout(Array(selectedAccounts.prefix(2)))
        } else {
            Text("QuotaGlance —")
                .font(.caption2)
        }
    }

    private func singleAccountLayout(_ account: AccountUsagePresentation) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 3) {
                    accountIdentity(account)
                    Spacer(minLength: 2)
                    Text(String(localized: "Updated"))
                        .foregroundStyle(QuotaGlanceTheme.secondaryText)
                    updatedDate(account.snapshot)
                }
                HStack(spacing: 3) {
                    accountIdentity(account)
                    Spacer(minLength: 2)
                    Image(systemName: "clock")
                        .foregroundStyle(QuotaGlanceTheme.secondaryText)
                    updatedDate(account.snapshot)
                }
            }
            quotaRow(label: "5H", window: account.snapshot?.session)
            if hasProFeatures {
                quotaRow(label: "W", window: account.snapshot?.weekly)
            }
        }
        .font(.caption2)
    }

    private func dualAccountLayout(_ accounts: [AccountUsagePresentation]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 3) {
                    Text(String(localized: "Updated"))
                    updatedDate(latestSnapshot(in: accounts))
                }
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                    updatedDate(latestSnapshot(in: accounts))
                }
            }
            .foregroundStyle(QuotaGlanceTheme.secondaryText)

            ForEach(accounts) { account in
                HStack(spacing: 3) {
                    compactAccountIdentity(account)
                    Spacer(minLength: 2)
                    HStack(spacing: 3) {
                        Text("5H")
                            .foregroundStyle(QuotaGlanceTheme.secondaryText)
                        Text(remainingPercentage(account.snapshot?.session))
                            .fontWeight(.semibold)
                        Text("W")
                            .foregroundStyle(QuotaGlanceTheme.secondaryText)
                        Text(remainingPercentage(account.snapshot?.weekly))
                            .fontWeight(.semibold)
                    }
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .font(.caption2)
    }

    private func accountIdentity(_ account: AccountUsagePresentation) -> some View {
        HStack(spacing: 3) {
            Text(providerSymbol(account.provider))
                .foregroundStyle(account.provider.accent)
            Text(account.displayName)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
        }
    }

    private func compactAccountIdentity(_ account: AccountUsagePresentation) -> some View {
        ViewThatFits(in: .horizontal) {
            accountIdentity(account)
                .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 3) {
                Text(providerSymbol(account.provider))
                    .foregroundStyle(account.provider.accent)
                Text(String(account.displayName.prefix(1)))
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func quotaRow(label: String, window: UsageWindow?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(QuotaGlanceTheme.secondaryText)
            Text(remainingPercentage(window))
                .fontWeight(.semibold)
                .monospacedDigit()
            Spacer(minLength: 2)
            Text("↻")
                .foregroundStyle(QuotaGlanceTheme.secondaryText)
            Text(compactDateTime(window?.resetAt))
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
        }
        .lineLimit(1)
    }

    private func updatedDate(_ snapshot: UsageSnapshot?) -> some View {
        Text(compactDateTime(snapshot?.updatedAt))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var inlineText: String {
        let displayLimit = entry.envelope?.displayLimit ?? .fiveHour
        let values = selectedAccounts.prefix(2).map { account in
            let window = account.snapshot.flatMap { displayLimit.window(in: $0) }
            return "\(providerSymbol(account.provider)) \(account.displayName) \(remainingPercentage(window))"
        }
        return values.isEmpty ? "QuotaGlance —" : values.joined(separator: " · ")
    }

    private var updatedTime: String {
        compactDateTime(latestSnapshot(in: selectedAccounts)?.updatedAt)
    }

    private func latestSnapshot(in accounts: [AccountUsagePresentation]) -> UsageSnapshot? {
        accounts.compactMap(\.snapshot).max { $0.updatedAt < $1.updatedAt }
    }

    private func providerSymbol(_ provider: AIProvider) -> String {
        switch provider {
        case .codex: "◎"
        case .claude: "✳︎"
        }
    }

    private func remainingPercentage(_ window: UsageWindow?) -> String {
        window.map { "\($0.roundedRemainingPercentage)%" } ?? "—"
    }

    private func compactDateTime(_ date: Date?) -> String {
        date.map { UsageFormatting.compactDateTime($0) } ?? "—"
    }

    private func accessibilityValue(_ snapshot: UsageSnapshot?) -> String {
        let displayLimit = entry.envelope?.displayLimit ?? .fiveHour
        let remaining = snapshot.flatMap { displayLimit.window(in: $0) }.map {
            String(localized: "percent.value", defaultValue: "\($0.roundedRemainingPercentage) percent")
        } ?? String(localized: "not available")
        return String(localized: "remaining.updated", defaultValue: "\(remaining), updated \(updatedTime)")
    }

    private func limitAccessibilityLabel(_ limit: QuotaDisplayLimit) -> String {
        switch limit {
        case .fiveHour: String(localized: "5 hour remaining")
        case .weekly: String(localized: "Weekly remaining")
        }
    }
}

private enum ComplicationPreview {
    private static let codexID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let claudeID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private static let updatedAt = Date(timeIntervalSince1970: 1_777_777_777)
    private static let sessionReset = Date(timeIntervalSince1970: 1_777_795_777)
    private static let weeklyReset = Date(timeIntervalSince1970: 1_778_382_177)
    private static let accounts = [
        AccountDisplayMetadata(id: codexID, provider: .codex, ordinal: 1, displayName: "sou"),
        AccountDisplayMetadata(id: claudeID, provider: .claude, ordinal: 1, displayName: "song"),
    ]
    private static let snapshots = [
        UsageSnapshot(
            provider: .codex,
            accountIdentifier: codexID,
            session: UsageWindow(usedPercentage: 18, resetAt: sessionReset),
            weekly: UsageWindow(usedPercentage: 36, resetAt: weeklyReset),
            updatedAt: updatedAt
        ),
        UsageSnapshot(
            provider: .claude,
            accountIdentifier: claudeID,
            session: UsageWindow(usedPercentage: 0, resetAt: sessionReset),
            weekly: UsageWindow(usedPercentage: 3, resetAt: weeklyReset),
            updatedAt: updatedAt
        ),
    ]

    static let singleEnvelope = SnapshotEnvelope(
        snapshots: snapshots,
        accounts: accounts,
        watchAccountIdentifiers: [codexID]
    )
    static let dualEnvelope = SnapshotEnvelope(
        snapshots: snapshots,
        accounts: accounts,
        watchAccountIdentifiers: [codexID, claudeID]
    )
}

#Preview(as: .accessoryRectangular) {
    QuotaGlanceComplication()
} timeline: {
    ComplicationEntry(date: Date(), envelope: ComplicationPreview.singleEnvelope)
}

#Preview(as: .accessoryRectangular) {
    QuotaGlanceComplication()
} timeline: {
    ComplicationEntry(date: Date(), envelope: ComplicationPreview.dualEnvelope)
}

#Preview(as: .accessoryCircular) {
    QuotaGlanceComplication()
} timeline: {
    ComplicationEntry(date: Date(), envelope: ComplicationPreview.singleEnvelope)
}
