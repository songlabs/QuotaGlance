import QuotaGlanceCore
import SwiftUI

enum QuotaGlanceTheme {
    static let appBackground = Color(red: 8.0 / 255.0, green: 12.0 / 255.0, blue: 20.0 / 255.0)
    static let cardBackground = Color(red: 21.0 / 255.0, green: 26.0 / 255.0, blue: 35.0 / 255.0)
    static let secondarySurface = Color(red: 29.0 / 255.0, green: 35.0 / 255.0, blue: 48.0 / 255.0)

    static let primaryText = Color(red: 245.0 / 255.0, green: 247.0 / 255.0, blue: 250.0 / 255.0)
    static let secondaryText = Color(red: 154.0 / 255.0, green: 163.0 / 255.0, blue: 178.0 / 255.0)
    static let tertiaryText = Color(red: 100.0 / 255.0, green: 109.0 / 255.0, blue: 124.0 / 255.0)

    static let brandAccent = Color(red: 85.0 / 255.0, green: 221.0 / 255.0, blue: 112.0 / 255.0)
    static let claudeAccent = Color(red: 255.0 / 255.0, green: 122.0 / 255.0, blue: 47.0 / 255.0)
    static let attention = Color(red: 255.0 / 255.0, green: 177.0 / 255.0, blue: 74.0 / 255.0)
    static let low = Color(red: 255.0 / 255.0, green: 91.0 / 255.0, blue: 96.0 / 255.0)

    static let border = Color.white.opacity(0.08)
    static let track = Color(red: 100.0 / 255.0, green: 109.0 / 255.0, blue: 124.0 / 255.0).opacity(0.32)

    static let cardCornerRadius: CGFloat = 18
    static let cardPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 18
}

extension AIProvider {
    var accent: Color {
        switch self {
        case .codex: QuotaGlanceTheme.brandAccent
        case .claude: QuotaGlanceTheme.claudeAccent
        }
    }
}

extension View {
    func quotaCardSurface(cornerRadius: CGFloat = QuotaGlanceTheme.cardCornerRadius) -> some View {
        background(
            QuotaGlanceTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(QuotaGlanceTheme.border)
        }
    }
}

struct QuotaGlanceBrandIcon: View {
    let size: CGFloat

    var body: some View {
        Image("QuotaGlanceBrandIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct QuotaProgressBar: View {
    let percentage: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(QuotaGlanceTheme.track)
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * CGFloat(min(100, max(0, percentage))) / 100)
            }
        }
        .frame(height: 6)
    }
}
