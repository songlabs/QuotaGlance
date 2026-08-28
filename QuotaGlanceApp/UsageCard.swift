import QuotaGlanceCore
import SwiftUI

struct UsageCard: View {
    let snapshot: UsageSnapshot
    let accountName: String
    let showsWeekly: Bool
    let isRefreshing: Bool
    let errorMessage: String?
    let refresh: () async -> Void
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
