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
                        colors: [Color(red: 0.025, green: 0.04, blue: 0.075), Color.black],
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
                Text("QuotaGlance").font(.headline)
                Image(systemName: "iphone.and.arrow.forward")
                Text("Open the iPhone app to refresh usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func small(_ envelope: SnapshotEnvelope) -> some View {
        let provider = WidgetSnapshotReader.defaultProvider
        let snapshot = envelope.snapshot(for: provider) ?? envelope.snapshots[0]
        return VStack(alignment: .leading, spacing: 5) {
            Text(snapshot.provider.displayName.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent(snapshot.provider))
            Text(snapshot.session.map { "\($0.roundedRemainingPercentage)%" } ?? "—")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
            Label("5h remaining", systemImage: "clock")
                .font(.caption2)
            Text("Weekly \(snapshot.weekly.map { "\($0.roundedRemainingPercentage)%" } ?? "—")")
                .font(.caption.bold())
            Spacer(minLength: 0)
            Text(UsageFormatting.updatedText(updatedAt: snapshot.updatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ envelope: SnapshotEnvelope) -> some View {
        HStack(spacing: 12) {
            ForEach(AIProvider.allCases) { provider in
                if let snapshot = envelope.snapshot(for: provider) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(provider.displayName.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accent(provider))
                        Text(snapshot.session.map { "\($0.roundedRemainingPercentage)%" } ?? "—")
                            .font(.title.bold())
                            .monospacedDigit()
                        Text("5h remaining").font(.caption2).foregroundStyle(.secondary)
                        Text("Weekly \(snapshot.weekly.map { "\($0.roundedRemainingPercentage)%" } ?? "—")")
                            .font(.caption.bold())
                        Spacer(minLength: 0)
                        Text(UsageFormatting.updatedText(updatedAt: snapshot.updatedAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func accent(_ provider: AIProvider) -> Color {
        provider == .codex ? .green : .orange
    }
}

private enum WidgetSnapshotReader {
    static let suiteName = "group.com.songlabs.QuotaGlance"
    static let key = "usageSnapshotEnvelope"
    static let defaultProviderKey = "defaultProvider"

    static func load() -> SnapshotEnvelope? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key) else { return nil }
        return try? SnapshotCoding.decode(data)
    }

    static var defaultProvider: AIProvider {
        UserDefaults(suiteName: suiteName)?.string(forKey: defaultProviderKey).flatMap(AIProvider.init(rawValue:)) ?? .codex
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
