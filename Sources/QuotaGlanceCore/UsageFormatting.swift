import Foundation

public enum UsageFormatting {
    public static func updatedText(updatedAt: Date, now: Date = Date()) -> String {
        let elapsed = max(0, now.timeIntervalSince(updatedAt))
        switch elapsed {
        case ..<60:
            return NSLocalizedString("Updated just now", comment: "Most recent usage refresh time")
        case ..<3_600:
            let minutes = Int(elapsed / 60)
            let format = NSLocalizedString("Updated %lld min ago", comment: "Usage refresh age in minutes")
            return String(format: format, Int64(minutes))
        case ..<86_400:
            let hours = Int(elapsed / 3_600)
            let format = NSLocalizedString("Updated %lldh ago", comment: "Usage refresh age in hours")
            return String(format: format, Int64(hours))
        default:
            let days = Int(elapsed / 86_400)
            let format = NSLocalizedString("Updated %lldd ago", comment: "Usage refresh age in days")
            return String(format: format, Int64(days))
        }
    }

    public static func isStale(updatedAt: Date, now: Date = Date(), maxAge: TimeInterval = 900) -> Bool {
        now.timeIntervalSince(updatedAt) > maxAge
    }
}
