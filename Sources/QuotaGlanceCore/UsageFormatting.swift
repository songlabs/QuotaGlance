import Foundation

public enum UsageFormatting {
    public static func updatedText(updatedAt: Date, now: Date = Date()) -> String {
        let elapsed = max(0, now.timeIntervalSince(updatedAt))
        switch elapsed {
        case ..<60:
            return "Updated just now"
        case ..<3_600:
            return "Updated \(Int(elapsed / 60)) min ago"
        case ..<86_400:
            let hours = Int(elapsed / 3_600)
            return "Updated \(hours)h ago"
        default:
            let days = Int(elapsed / 86_400)
            return "Updated \(days)d ago"
        }
    }

    public static func isStale(updatedAt: Date, now: Date = Date(), maxAge: TimeInterval = 900) -> Bool {
        now.timeIntervalSince(updatedAt) > maxAge
    }
}
