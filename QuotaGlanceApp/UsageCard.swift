import QuotaGlanceCore
import SwiftUI

struct UsageCard: View {
    let snapshot: UsageSnapshot
    let accountName: String
    let showsWeekly: Bool
    let isRefreshing: Bool
    let errorMessage: String?
    let resetCreditDetails: CodexResetCreditDetails?
    let isLoadingResetCreditDetails: Bool
    let resetCreditDetailsErrorMessage: String?
    let refresh: () async -> Void
    let loadResetCreditDetails: () async -> Void
    let reconnect: (() async -> Void)?
    @Environment(\.locale) private var locale

    private var primaryWindow: UsageWindow? { snapshot.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(accountName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(QuotaGlanceTheme.primaryText)
                Spacer()
                if isRefreshing {
                    ProgressView().controlSize(.small).tint(snapshot.provider.accent)
                }
                if isStale {
                    Label(AppLocalization.string("Cached", locale: locale), systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(QuotaGlanceTheme.secondaryText)
                }
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
                .accessibilityLabel(AppLocalization.string("Refresh account", locale: locale))
            }

            HStack(alignment: .center, spacing: 18) {
                UsageRing(window: primaryWindow, accent: snapshot.provider.accent)
                    .frame(width: 108, height: 108)
                    .layoutPriority(1)

                VStack(alignment: .leading, spacing: 10) {
                    Text(AppLocalization.string("5h remaining", locale: locale))
                        .font(.headline)
                        .foregroundStyle(QuotaGlanceTheme.primaryText)
                    Text(resetText(primaryWindow?.resetAt))
                        .font(.subheadline)
                        .foregroundStyle(QuotaGlanceTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    if primaryWindow == nil {
                        Text(AppLocalization.string("Not reported by provider", locale: locale))
                            .font(.caption2)
                            .foregroundStyle(QuotaGlanceTheme.tertiaryText)
                    }

                    if showsWeekly {
                        Divider().overlay(QuotaGlanceTheme.border)
                        WeeklyRow(window: snapshot.weekly, accent: snapshot.provider.accent)
                    }

                    if ResetCreditPresentationPolicy.showsRow(
                        provider: snapshot.provider,
                        availableCount: snapshot.availableResetCount
                    ), let availableResetCount = snapshot.availableResetCount {
                        ResetCreditsSection(
                            provider: snapshot.provider,
                            availableCount: availableResetCount,
                            details: resetCreditDetails,
                            isLoading: isLoadingResetCreditDetails,
                            errorMessage: resetCreditDetailsErrorMessage,
                            loadDetails: loadResetCreditDetails
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(QuotaGlanceTheme.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let reconnect {
                Button(AppLocalization.string(
                    "reconnect.provider",
                    defaultValue: "Reconnect %@",
                    locale: locale,
                    arguments: [snapshot.provider.displayName]
                )) {
                    Task { await reconnect() }
                }
                .buttonStyle(.bordered)
                .tint(snapshot.provider.accent)
            }
        }
        .padding(QuotaGlanceTheme.cardPadding)
        .quotaCardSurface()
        .accessibilityElement(children: .contain)
    }

    private var isStale: Bool {
        UsageFormatting.isStale(updatedAt: snapshot.updatedAt)
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return AppLocalization.string("Reset —", locale: locale) }
        let time = localDateTime(date, locale: locale)
        return AppLocalization.string("reset.time", defaultValue: "Reset %@", locale: locale, arguments: [time])
    }
}

private struct ResetCreditsSection: View {
    let provider: AIProvider
    let availableCount: Int
    let details: CodexResetCreditDetails?
    let isLoading: Bool
    let errorMessage: String?
    let loadDetails: () async -> Void
    @Environment(\.locale) private var locale
    @State private var isExpanded = false

    private var canExpand: Bool {
        ResetCreditPresentationPolicy.allowsExpansion(
            provider: provider,
            availableCount: availableCount
        )
    }

    private var availableCredits: [CodexResetCredit] {
        details.map { ResetCreditPresentationPolicy.sortedAvailableCredits(in: $0) } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canExpand {
                Button(action: toggleExpansion) {
                    summaryRow(showsChevron: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppLocalization.string(
                    isExpanded ? "Collapse reset details" : "Expand reset details",
                    locale: locale
                ))
            } else {
                summaryRow(showsChevron: false)
            }

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: availableCount) { _, newValue in
            if newValue <= 0 {
                isExpanded = false
            }
        }
    }

    private func toggleExpansion() {
        let willExpand = !isExpanded
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded = willExpand
        }
        if willExpand, details == nil, !isLoading {
            Task { await loadDetails() }
        }
    }

    private func summaryRow(showsChevron: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(AppLocalization.string("Banked resets", locale: locale))
                .foregroundStyle(QuotaGlanceTheme.secondaryText)
            Spacer(minLength: 6)
            Text(verbatim: summaryText)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if showsChevron {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(QuotaGlanceTheme.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var expandedContent: some View {
        if isLoading || (details == nil && errorMessage == nil) {
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini).tint(provider.accent)
                Text(AppLocalization.string("Loading reset details…", locale: locale))
            }
            .font(.caption2)
            .foregroundStyle(QuotaGlanceTheme.secondaryText)
            .padding(.leading, 10)
        } else if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(QuotaGlanceTheme.attention)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 10)
        } else if availableCredits.isEmpty {
            Text(AppLocalization.string("No reset details reported.", locale: locale))
                .font(.caption2)
                .foregroundStyle(QuotaGlanceTheme.tertiaryText)
                .padding(.leading, 10)
        } else {
            ForEach(availableCredits) { credit in
                ResetCreditDetailRow(credit: credit)
                    .padding(.leading, 10)
            }
        }
    }

    private var summaryText: String {
        let countText = AppLocalization.string(
            availableCount == 1 ? "reset.count.one" : "reset.count.other",
            defaultValue: availableCount == 1 ? "%lld reset" : "%lld resets",
            locale: locale,
            arguments: [availableCount]
        )
        guard availableCount > 0,
              let details,
              let expiration = ResetCreditPresentationPolicy.nearestExpiration(in: details)
        else { return countText }
        return AppLocalization.string(
            "reset.count.until",
            defaultValue: "%@ · until %@",
            locale: locale,
            arguments: [countText, localResetDate(expiration, locale: locale)]
        )
    }
}

private struct ResetCreditDetailRow: View {
    let credit: CodexResetCredit
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: credit.providerTitle ?? AppLocalization.string(
                "Reset detail",
                locale: locale
            ))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 6)
            if let expiresAt = credit.expiresAt {
                Text(verbatim: AppLocalization.string(
                    "reset.expires",
                    defaultValue: "Until %@",
                    locale: locale,
                    arguments: [localResetDateTime(expiresAt, locale: locale)]
                ))
                    .foregroundStyle(QuotaGlanceTheme.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .font(.caption2)
        .foregroundStyle(QuotaGlanceTheme.primaryText)
    }
}

private struct UsageRing: View {
    let window: UsageWindow?
    let accent: Color
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack {
            Circle().stroke(QuotaGlanceTheme.track, lineWidth: 9)
            Circle()
                .trim(from: 0, to: (window?.remainingPercentage ?? 0) / 100)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(window.map { "\($0.roundedRemainingPercentage)%" } ?? "—")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .foregroundStyle(QuotaGlanceTheme.primaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.string("5 hour remaining", locale: locale))
        .accessibilityValue(window.map {
            AppLocalization.string(
                "percent.value",
                defaultValue: "%lld percent",
                locale: locale,
                arguments: [$0.roundedRemainingPercentage]
            )
        } ?? AppLocalization.string("Not available", locale: locale))
    }

    private var ringColor: Color {
        window == nil ? QuotaGlanceTheme.tertiaryText : accent
    }
}

private struct WeeklyRow: View {
    let window: UsageWindow?
    let accent: Color
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(AppLocalization.string("Weekly", locale: locale))
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text(window.map { "\($0.roundedRemainingPercentage)%" } ?? "—")
                    .font(.subheadline.bold())
                    .monospacedDigit()
            }

            QuotaProgressBar(
                percentage: window?.remainingPercentage ?? 0,
                color: window == nil ? QuotaGlanceTheme.tertiaryText : accent
            )
            .accessibilityLabel(AppLocalization.string("Weekly remaining", locale: locale))

            if let resetAt = window?.resetAt {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(AppLocalization.string("Next update", locale: locale))
                        .foregroundStyle(QuotaGlanceTheme.secondaryText)
                    Spacer()
                    Text(localDateTime(resetAt, locale: locale))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .font(.caption)
            } else if window != nil {
                Text(AppLocalization.string("Update time not provided", locale: locale))
                    .font(.caption)
                    .foregroundStyle(QuotaGlanceTheme.tertiaryText)
            }
        }
    }
}

func localDateTime(_ date: Date, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func localResetDate(_ date: Date, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = .autoupdatingCurrent
    formatter.setLocalizedDateFormatFromTemplate("Md")
    return formatter.string(from: date)
}

private func localResetDateTime(_ date: Date, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = .autoupdatingCurrent
    formatter.setLocalizedDateFormatFromTemplate("Mdjm")
    return formatter.string(from: date)
}
