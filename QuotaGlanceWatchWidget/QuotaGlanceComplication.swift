import AppIntents
import QuotaGlanceCore
import SwiftUI
import WidgetKit

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let envelope: SnapshotEnvelope?
    let configuredAccountIdentifier: UUID?
    let configuredDisplayLimit: QuotaDisplayLimit?
}

enum ComplicationLimitOption: String, AppEnum {
    case fiveHour
    case weekly

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Limit"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .fiveHour: "5H",
        .weekly: "Weekly",
    ]

    var displayLimit: QuotaDisplayLimit {
        switch self {
        case .fiveHour: .fiveHour
        case .weekly: .weekly
        }
    }

    init(_ displayLimit: QuotaDisplayLimit) {
        switch displayLimit {
        case .fiveHour: self = .fiveHour
        case .weekly: self = .weekly
        }
    }
}

struct ComplicationAccountEntity: AppEntity, Hashable {
    let id: String
    let providerName: String
    let displayName: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = ComplicationAccountQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(providerName) / \(displayName)")
    }

    init(_ account: AccountUsagePresentation) {
        id = account.accountIdentifier?.uuidString ?? account.id
        providerName = account.provider.displayName
        displayName = account.displayName
    }
}

struct ComplicationAccountQuery: EntityQuery {
    func entities(for identifiers: [ComplicationAccountEntity.ID]) async throws -> [ComplicationAccountEntity] {
        let entities = availableEntities()
        return identifiers.compactMap { identifier in
            entities.first { $0.id == identifier }
        }
    }

    func suggestedEntities() async throws -> [ComplicationAccountEntity] {
        availableEntities()
    }

    private func availableEntities(at date: Date = Date()) -> [ComplicationAccountEntity] {
        SharedWatchSnapshotCache().load()?
            .watchAccountPresentations(at: date)
            .map(ComplicationAccountEntity.init) ?? []
    }
}

struct ComplicationConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Configure Circular Complication"
    static let description = IntentDescription(
        "Choose an account and quota limit for this circular complication."
    )

    @Parameter(title: "Account")
    var account: ComplicationAccountEntity?

    @Parameter(title: "Limit")
    var limit: ComplicationLimitOption?

    init() {}

    init(account: ComplicationAccountEntity?, limit: ComplicationLimitOption?) {
        self.account = account
        self.limit = limit
    }
}

struct ComplicationProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(
            date: Date(),
            envelope: ComplicationPreview.dualEnvelope,
            configuredAccountIdentifier: nil,
            configuredDisplayLimit: nil
        )
    }

    func snapshot(
        for configuration: ComplicationConfigurationIntent,
        in context: Context
    ) async -> ComplicationEntry {
        let envelope = SharedWatchSnapshotCache().load() ?? (context.isPreview ? ComplicationPreview.dualEnvelope : nil)
        return entry(date: Date(), envelope: envelope, configuration: configuration)
    }

    func timeline(
        for configuration: ComplicationConfigurationIntent,
        in context: Context
    ) async -> Timeline<ComplicationEntry> {
        let now = Date()
        let envelope = SharedWatchSnapshotCache().load()
        let refreshInterval: TimeInterval = envelope == nil ? 60 : 15 * 60
        let entries = (envelope?.timelineEntryDates(from: now) ?? [now]).map {
            entry(date: $0, envelope: envelope, configuration: configuration)
        }
        return Timeline(
            entries: entries,
            policy: .after(now.addingTimeInterval(refreshInterval))
        )
    }

    func recommendations() -> [AppIntentRecommendation<ComplicationConfigurationIntent>] {
        if #available(watchOS 26.0, *) {
            return []
        }
        guard let envelope = SharedWatchSnapshotCache().load() else { return [] }
        let date = Date()
        let accounts = envelope.watchAccountPresentations(at: date).map(ComplicationAccountEntity.init)
        let limits: [QuotaDisplayLimit] = envelope.hasProFeatures(at: date)
            ? QuotaDisplayLimit.allCases
            : [.fiveHour]
        return accounts.flatMap { account in
            limits.map { limit in
                let intent = ComplicationConfigurationIntent(
                    account: account,
                    limit: ComplicationLimitOption(limit)
                )
                let limitName = switch limit {
                case .fiveHour: String(localized: "5H")
                case .weekly: String(localized: "Weekly")
                }
                return AppIntentRecommendation(
                    intent: intent,
                    description: "\(account.providerName) / \(account.displayName) · \(limitName)"
                )
            }
        }
    }

    private func entry(
        date: Date,
        envelope: SnapshotEnvelope?,
        configuration: ComplicationConfigurationIntent
    ) -> ComplicationEntry {
        ComplicationEntry(
            date: date,
            envelope: envelope,
            configuredAccountIdentifier: configuration.account.flatMap { UUID(uuidString: $0.id) },
            configuredDisplayLimit: configuration.limit?.displayLimit
        )
    }
}

struct QuotaGlanceComplication: Widget {
    let kind = "QuotaGlanceComplication"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ComplicationConfigurationIntent.self,
            provider: ComplicationProvider()
        ) { entry in
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
        let selection = entry.envelope?.circularComplicationSelection(
            configuredAccountIdentifier: entry.configuredAccountIdentifier,
            configuredDisplayLimit: entry.configuredDisplayLimit,
            at: entry.date
        ) ?? CircularComplicationSelection(account: nil, displayLimit: .fiveHour)
        let remaining = selection.window?.remainingPercentage
        return Gauge(value: remaining ?? 0, in: 0...100) {
            QuotaGlanceBrandIcon(size: 10)
                .widgetAccentable()
        } currentValueLabel: {
            Text(remaining.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.system(.caption, design: .rounded).bold())
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(selection.account?.provider.accent ?? QuotaGlanceTheme.brandAccent)
        .accessibilityLabel(limitAccessibilityLabel(selection.displayLimit))
        .accessibilityValue(accessibilityValue(selection))
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

    private func accessibilityValue(_ selection: CircularComplicationSelection) -> String {
        let remaining = selection.window.map {
            String(localized: "percent.value", defaultValue: "\($0.roundedRemainingPercentage) percent")
        } ?? String(localized: "not available")
        let updated = compactDateTime(selection.account?.snapshot?.updatedAt)
        return String(localized: "remaining.updated", defaultValue: "\(remaining), updated \(updated)")
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
    ComplicationEntry(
        date: Date(),
        envelope: ComplicationPreview.singleEnvelope,
        configuredAccountIdentifier: nil,
        configuredDisplayLimit: nil
    )
}

#Preview(as: .accessoryRectangular) {
    QuotaGlanceComplication()
} timeline: {
    ComplicationEntry(
        date: Date(),
        envelope: ComplicationPreview.dualEnvelope,
        configuredAccountIdentifier: nil,
        configuredDisplayLimit: nil
    )
}

#Preview(as: .accessoryCircular) {
    QuotaGlanceComplication()
} timeline: {
    ComplicationEntry(
        date: Date(),
        envelope: ComplicationPreview.singleEnvelope,
        configuredAccountIdentifier: nil,
        configuredDisplayLimit: nil
    )
}
