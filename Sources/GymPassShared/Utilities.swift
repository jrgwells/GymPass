import Foundation

public enum GymPassDate {
    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    private static func plainFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    /// Parses ISO-8601 with optional fractional seconds and numeric offsets.
    public static func parse(_ string: String) -> Date? {
        if let date = plainFormatter().date(from: string) { return date }
        if let date = fractionalFormatter().date(from: string) { return date }
        return nil
    }

    /// Parses a `D:HH:MM:SS` or `HH:MM:SS` style duration, allowing > 24h.
    public static func parseDuration(_ string: String) -> TimeInterval? {
        let parts = string.split(separator: ":").map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }
        let values = parts.compactMap(Int.init)
        guard values.count == parts.count else { return nil }
        let hours: Int
        let minutes: Int
        let seconds: Int
        if values.count == 4 {
            hours = values[0] * 24 + values[1]
            minutes = values[2]
            seconds = values[3]
        } else {
            hours = values[0]
            minutes = values[1]
            seconds = values[2]
        }
        return TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    public static func iso8601(_ date: Date) -> String {
        fractionalFormatter().string(from: date)
    }
}

public struct RGB: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var hexString: String {
        let r = Int((max(0, min(1, red)) * 255).rounded())
        let g = Int((max(0, min(1, green)) * 255).rounded())
        let b = Int((max(0, min(1, blue)) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

public enum HexColor {
    public static func rgb(from hex: String) -> RGB? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return RGB(red: r, green: g, blue: b)
    }

    public static func normalized(_ hex: String, fallback: String) -> String {
        rgb(from: hex)?.hexString ?? fallback
    }
}

public enum DurationFormatter {
    public static func minutesAgo(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        if seconds < 86400 { return "\(seconds / 3600) hr ago" }
        return "\(seconds / 86400) d ago"
    }

    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
