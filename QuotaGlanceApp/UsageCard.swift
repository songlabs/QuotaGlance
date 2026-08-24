import QuotaGlanceCore
import SwiftUI

struct UsageCard: View {
    let snapshot: UsageSnapshot
    let isRefreshing: Bool
    let errorMessage: String?
    let reconnect: (() async -> Void)?

    private var primaryWindow: UsageWindow? { snapshot.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(snapshot.provider.displayName)
                    .font(.headline)
                    .foregroundStyle(snapshot.provider.accent)
                Spacer()
                if isRefreshing {
                    ProgressView().controlSize(.small).tint(snapshot.provider.accent)
                }
            }

            HStack(spacing: 18) {
                UsageRing(window: primaryWindow, accent: snapshot.provider.accent)
                    .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: 6) {
                    Text("5h remaining")
                        .font(.headline)
                    Text(resetText(primaryWindow?.resetAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if primaryWindow == nil {
                        Text("Not reported by provider")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(.white.opacity(0.08))
            WeeklyRow(window: snapshot.weekly, accent: snapshot.provider.accent)

            HStack(alignment: .firstTextBaseline) {
                Text(UsageFormatting.updatedText(updatedAt: snapshot.updatedAt))
                    .foregroundStyle(isStale ? .secondary : .tertiary)
                Spacer()
                if isStale {
                    Label("Cached", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let reconnect {
                Button(String(localized: "reconnect.provider", defaultValue: "Reconnect \(snapshot.provider.displayName)")) {
                    Task { await reconnect() }
                }
                .buttonStyle(.bordered)
                .tint(snapshot.provider.accent)
            }
        }
        .padding(18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.055))
        }
        .accessibilityElement(children: .contain)
    }

    private var isStale: Bool {
        UsageFormatting.isStale(updatedAt: snapshot.updatedAt)
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return String(localized: "Reset —") }
        let time = date.formatted(date: .omitted, time: .shortened)
        return String(localized: "reset.time", defaultValue: "Reset \(time)")
    }
}

private struct UsageRing: View {
    let window: UsageWindow?
    let accent: Color

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: 8)
            Circle()
                .trim(from: 0, to: (window?.remainingPercentage ?? 0) / 100)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(window.map { "\($0.roundedRemainingPercentage)%" } ?? "—")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("5 hour remaining")
        .accessibilityValue(window.map {
            String(localized: "percent.value", defaultValue: "\($0.roundedRemainingPercentage) percent")
        } ?? String(localized: "Not available"))
    }

    private var ringColor: Color {
        guard let window else { return .secondary }
        return window.level.color(normal: accent)
    }
}

private struct WeeklyRow: View {
    let window: UsageWindow?
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Text("Weekly")
                .font(.subheadline.weight(.medium))
                .frame(width: 58, alignment: .leading)
            ProgressView(value: window?.remainingPercentage ?? 0, total: 100)
                .tint(window?.level.color(normal: accent) ?? .secondary)
                .accessibilityLabel("Weekly remaining")
            Text(window.map { "\($0.roundedRemainingPercentage)%" } ?? "—")
                .font(.subheadline.bold())
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
    }
}

extension AIProvider {
    var accent: Color {
        switch self {
        case .codex: Color(red: 0.35, green: 0.88, blue: 0.39)
        case .claude: Color(red: 1.0, green: 0.48, blue: 0.16)
        }
    }
}

extension RemainingLevel {
    func color(normal: Color) -> Color {
        switch self {
        case .normal: normal
        case .attention: .orange
        case .low: .red
        }
    }
}
