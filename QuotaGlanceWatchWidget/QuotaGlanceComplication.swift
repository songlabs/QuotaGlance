import QuotaGlanceCore
import SwiftUI
import WidgetKit

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let envelope: SnapshotEnvelope?
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), envelope: ComplicationPreview.envelope)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        let envelope = SharedWatchSnapshotCache().load() ?? (context.isPreview ? ComplicationPreview.envelope : nil)
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

    private var circular: some View {
        let snapshot = entry.envelope?.snapshot(for: .codex) ?? entry.envelope?.snapshots.first
        let displayLimit = entry.envelope?.displayLimit ?? .fiveHour
        let window = snapshot.flatMap { displayLimit.window(in: $0) }
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
        .tint(snapshot?.provider.accent ?? QuotaGlanceTheme.brandAccent)
        .accessibilityLabel(limitAccessibilityLabel(displayLimit))
        .accessibilityValue(accessibilityValue(snapshot))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                QuotaGlanceBrandIcon(size: 10)
                    .widgetAccentable()
                Text("QuotaGlance").font(.caption2.bold())
                Spacer()
                Text(updatedTime).font(.caption2).foregroundStyle(QuotaGlanceTheme.secondaryText)
            }
            ForEach(AIProvider.allCases) { provider in
                if let snapshot = entry.envelope?.snapshot(for: provider) {
                    let displayLimit = entry.envelope?.displayLimit ?? .fiveHour
                    let window = displayLimit.window(in: snapshot)
                    HStack {
                        Text(provider.shortName).foregroundStyle(provider.accent)
                        Text(window.map { "\($0.roundedRemainingPercentage)%" } ?? "—")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Spacer()
                        Text(limitShortLabel(displayLimit)).foregroundStyle(QuotaGlanceTheme.secondaryText)
                    }
                    .font(.caption2)
                }
            }
        }
    }

    private var inlineText: String {
        let values = AIProvider.allCases.compactMap { provider -> String? in
            guard let snapshot = entry.envelope?.snapshot(for: provider) else { return nil }
            let displayLimit = entry.envelope?.displayLimit ?? .fiveHour
            let window = displayLimit.window(in: snapshot)
            return "\(provider.shortName) \(window.map { "\($0.roundedRemainingPercentage)%" } ?? "—")"
        }
        return values.isEmpty ? "QuotaGlance —" : values.joined(separator: " · ") + " · " + updatedTime
    }

    private var updatedTime: String {
        guard let date = entry.envelope?.snapshots.map(\.updatedAt).max() else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func accessibilityValue(_ snapshot: UsageSnapshot?) -> String {
        let displayLimit = entry.envelope?.displayLimit ?? .fiveHour
        let remaining = snapshot.flatMap { displayLimit.window(in: $0) }.map {
            String(localized: "percent.value", defaultValue: "\($0.roundedRemainingPercentage) percent")
        } ?? String(localized: "not available")
        return String(localized: "remaining.updated", defaultValue: "\(remaining), updated \(updatedTime)")
    }

    private func limitShortLabel(_ limit: QuotaDisplayLimit) -> String {
        switch limit {
        case .fiveHour: String(localized: "5h")
        case .weekly: String(localized: "Weekly")
        }
    }

    private func limitAccessibilityLabel(_ limit: QuotaDisplayLimit) -> String {
        switch limit {
        case .fiveHour: String(localized: "5 hour remaining")
        case .weekly: String(localized: "Weekly remaining")
        }
    }
}

private enum ComplicationPreview {
    static let envelope = SnapshotEnvelope(snapshots: [
        UsageSnapshot(provider: .codex, session: UsageWindow(usedPercentage: 28, resetAt: nil), weekly: UsageWindow(usedPercentage: 59, resetAt: nil), updatedAt: Date()),
        UsageSnapshot(provider: .claude, session: UsageWindow(usedPercentage: 52, resetAt: nil), weekly: UsageWindow(usedPercentage: 37, resetAt: nil), updatedAt: Date()),
    ])
}

#Preview(as: .accessoryCircular) {
    QuotaGlanceComplication()
} timeline: {
    ComplicationEntry(date: Date(), envelope: ComplicationPreview.envelope)
}

#Preview(as: .accessoryRectangular) {
    QuotaGlanceComplication()
} timeline: {
    ComplicationEntry(date: Date(), envelope: ComplicationPreview.envelope)
}

#Preview(as: .accessoryInline) {
    QuotaGlanceComplication()
} timeline: {
    ComplicationEntry(date: Date(), envelope: ComplicationPreview.envelope)
}
