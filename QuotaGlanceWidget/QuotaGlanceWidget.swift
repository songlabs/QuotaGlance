import QuotaGlanceCore
import SwiftUI
import WidgetKit

struct PhoneWidgetEntry: TimelineEntry {
    let date: Date
    let envelope: SnapshotEnvelope?
}
struct PhoneWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhoneWidgetEntry {
        PhoneWidgetEntry(date: Date(), envelope: WidgetPreviewData.envelope)
    }

    func getSnapshot(in context: Context, completion: @escaping (PhoneWidgetEntry) -> Void) {
        completion(PhoneWidgetEntry(date: Date(), envelope: WidgetSnapshotReader.load() ?? WidgetPreviewData.envelope))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhoneWidgetEntry>) -> Void) {
        let entry = PhoneWidgetEntry(date: Date(), envelope: WidgetSnapshotReader.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct QuotaGlanceWidget: Widget {
    let kind = "QuotaGlanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PhoneWidgetProvider()) { entry in
            PhoneWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [QuotaGlanceTheme.secondarySurface, QuotaGlanceTheme.appBackground],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("QuotaGlance")
        .description("Codex and Claude remaining usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct PhoneWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PhoneWidgetEntry

    var body: some View {
        if let envelope = entry.envelope, !envelope.snapshots.isEmpty {
            if family == .systemSmall {
                small(envelope)
            } else {
                medium(envelope)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("QuotaGlance")
                    .font(.headline)
                    .foregroundStyle(QuotaGlanceTheme.primaryText)
                Image(systemName: "iphone.and.arrow.forward")
                    .foregroundStyle(QuotaGlanceTheme.primaryText)
                Text("Open the iPhone app to refresh usage.")
                    .font(.caption)
                    .foregroundStyle(QuotaGlanceTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func small(_ envelope: SnapshotEnvelope) -> some View {
        let provider = WidgetSnapshotReader.defaultProvider
        let snapshot = envelope.snapshot(
            for: provider,
            accountIdentifier: WidgetSnapshotReader.selectedAccountIdentifier(for: provider)
        ) ?? envelope.snapshots[0]
        let displayLimit = WidgetSnapshotReader.displayLimit
        let window = displayLimit.window(in: snapshot)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                QuotaGlanceBrandIcon(size: 17)
                Text(snapshot.provider.displayName.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(snapshot.provider.accent)
            }
            Text(window.map { "\($0.roundedRemainingPercentage)%" } ?? "—")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(QuotaGlanceTheme.primaryText)
            Label(limitLabel(displayLimit), systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(QuotaGlanceTheme.secondaryText)
            Spacer(minLength: 0)
            Text(UsageFormatting.updatedText(updatedAt: snapshot.updatedAt))
                .font(.caption2)
                .foregroundStyle(QuotaGlanceTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ envelope: SnapshotEnvelope) -> some View {
        HStack(spacing: 12) {
            ForEach(AIProvider.allCases) { provider in
                if let snapshot = envelope.snapshot(
                    for: provider,
                    accountIdentifier: WidgetSnapshotReader.selectedAccountIdentifier(for: provider)
                ) {
                    let displayLimit = WidgetSnapshotReader.displayLimit
                    let window = displayLimit.window(in: snapshot)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(provider.displayName.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(provider.accent)
                        Text(window.map { "\($0.roundedRemainingPercentage)%" } ?? "—")
                            .font(.title.bold())
                            .monospacedDigit()
                            .foregroundStyle(QuotaGlanceTheme.primaryText)
                        Text(limitLabel(displayLimit))
                            .font(.caption2)
                            .foregroundStyle(QuotaGlanceTheme.secondaryText)
                        Spacer(minLength: 0)
                        Text(UsageFormatting.updatedText(updatedAt: snapshot.updatedAt))
                            .font(.caption2)
                            .foregroundStyle(QuotaGlanceTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func limitLabel(_ limit: QuotaDisplayLimit) -> String {
        switch limit {
        case .fiveHour: String(localized: "5 hours")
        case .weekly: String(localized: "Weekly")
        }
    }
}

private enum WidgetSnapshotReader {
    static let suiteName = "group.com.songlabs.QuotaGlance"
    static let key = "usageSnapshotEnvelope"
    static let defaultProviderKey = "defaultProvider"
    static let displayLimitKey = "displayLimit"
    static let selectedAccountKeyPrefix = "selectedAccount."

    static func load() -> SnapshotEnvelope? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key) else { return nil }
        return try? SnapshotCoding.decode(data)
    }

    static var defaultProvider: AIProvider {
        UserDefaults(suiteName: suiteName)?.string(forKey: defaultProviderKey).flatMap(AIProvider.init(rawValue:)) ?? .codex
    }

    static var displayLimit: QuotaDisplayLimit {
        UserDefaults(suiteName: suiteName)?.string(forKey: displayLimitKey).flatMap(QuotaDisplayLimit.init(rawValue:)) ?? .fiveHour
    }

    static func selectedAccountIdentifier(for provider: AIProvider) -> UUID? {
        UserDefaults(suiteName: suiteName)?
            .string(forKey: selectedAccountKeyPrefix + provider.rawValue)
            .flatMap(UUID.init(uuidString:))
    }
}

private enum WidgetPreviewData {
    static let envelope = SnapshotEnvelope(snapshots: [
        UsageSnapshot(provider: .codex, session: UsageWindow(usedPercentage: 28, resetAt: nil), weekly: UsageWindow(usedPercentage: 59, resetAt: nil), updatedAt: Date()),
        UsageSnapshot(provider: .claude, session: UsageWindow(usedPercentage: 52, resetAt: nil), weekly: UsageWindow(usedPercentage: 37, resetAt: nil), updatedAt: Date()),
    ])
}

#Preview(as: .systemSmall) {
    QuotaGlanceWidget()
} timeline: {
    PhoneWidgetEntry(date: Date(), envelope: WidgetPreviewData.envelope)
}

#Preview(as: .systemMedium) {
    QuotaGlanceWidget()
} timeline: {
    PhoneWidgetEntry(date: Date(), envelope: WidgetPreviewData.envelope)
}
