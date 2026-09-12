import Foundation

enum ByteFormat {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB, .useBytes]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static func string(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }

    static func short(_ bytes: Int64) -> String {
        string(bytes)
    }
}

enum RelativeDate {
    static func string(from date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        let days = seconds / 86_400
        if days < 1 {
            let hours = max(1, Int(seconds / 3_600))
            return "\(hours)h ago"
        }
        return "\(Int(days.rounded()))d ago"
    }
}
