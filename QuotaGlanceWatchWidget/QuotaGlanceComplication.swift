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
        completion(ComplicationEntry(date: Date(), envelope: WatchWidgetCache.load() ?? ComplicationPreview.envelope))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        completion(Timeline(
            entries: [ComplicationEntry(date: Date(), envelope: WatchWidgetCache.load())],
            policy: .after(Date().addingTimeInterval(15 * 60))
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
        let remaining = snapshot?.session?.remainingPercentage
        return Gauge(value: remaining ?? 0, in: 0...100) {
            Text(snapshot?.provider.shortName ?? "Q")
        } currentValueLabel: {
            Text(remaining.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.system(.caption, design: .rounded).bold())
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(snapshot?.provider == .claude ? .orange : .green)
        .accessibilityLabel("5 hour remaining")
        .accessibilityValue(accessibilityValue(snapshot))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text("QuotaGlance").font(.caption2.bold())
                Spacer()
                Text(updatedTime).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(AIProvider.allCases) { provider in
                if let snapshot = entry.envelope?.snapshot(for: provider) {
                    HStack {
                        Text(provider.shortName).foregroundStyle(provider == .codex ? .green : .orange)
                        Text(snapshot.session.map { "\($0.roundedRemainingPercentage)%" } ?? "—")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Spacer()
                        Text("5h").foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                }
            }
        }
    }

    private var inlineText: String {
        let values = AIProvider.allCases.compactMap { provider -> String? in
            guard let snapshot = entry.envelope?.snapshot(for: provider) else { return nil }
            return "\(provider.shortName) \(snapshot.session.map { "\($0.roundedRemainingPercentage)%" } ?? "—")"
        }
        return values.isEmpty ? "QuotaGlance —" : values.joined(separator: " · ") + " · " + updatedTime
    }

    private var updatedTime: String {
        guard let date = entry.envelope?.snapshots.map(\.updatedAt).max() else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func accessibilityValue(_ snapshot: UsageSnapshot?) -> String {
        let remaining = snapshot?.session.map { "\($0.roundedRemainingPercentage) percent" } ?? "not available"
        return "\(remaining), updated \(updatedTime)"
    }
}

private enum WatchWidgetCache {
    static func load() -> SnapshotEnvelope? {
        guard let data = UserDefaults(suiteName: "group.com.songlabs.QuotaGlance.watch")?
            .data(forKey: "usageSnapshotEnvelope")
        else { return nil }
        return try? SnapshotCoding.decode(data)
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
