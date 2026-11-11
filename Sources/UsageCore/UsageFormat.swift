import Foundation

public enum UsageFormat {
    /// Compact time remaining, e.g. "3d 4h", "2h 14m", "9m", "<1m".
    public static func countdown(to date: Date, from now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "now" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    /// Time since a past date, e.g. "just now", "4m ago", "2h ago".
    public static func ago(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}
