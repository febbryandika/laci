import Foundation

/// Dates for files (SPEC §5.2): ISO 8601 assembled from calendar components in an explicit zone.
/// No `Locale` and no `FormatStyle` anywhere here, so the output cannot follow the device.
public enum ISODate {
    /// `2026-09-13T15:04:05+07:00`
    public static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let parts = components(of: date, in: timeZone)
        let offset = timeZone.secondsFromGMT(for: date)
        let sign = offset < 0 ? "-" : "+"
        let magnitude = abs(offset)
        let zone = sign + pad(magnitude / 3600) + ":" + pad(magnitude % 3600 / 60)
        return day(parts) + "T" + time(parts, separator: ":") + zone
    }

    /// `2026-09-13`
    public static func day(_ date: Date, timeZone: TimeZone) -> String {
        day(components(of: date, in: timeZone))
    }

    /// `20260913-150405`: sorts by time and is legal in a file name on every file system.
    public static func compact(_ date: Date, timeZone: TimeZone) -> String {
        let parts = components(of: date, in: timeZone)
        return pad(parts.year, 4) + pad(parts.month) + pad(parts.day) + "-" + time(parts, separator: "")
    }

    private struct Parts {
        let year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int
    }

    private static func components(of date: Date, in timeZone: TimeZone) -> Parts {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return Parts(
            year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0,
            hour: parts.hour ?? 0, minute: parts.minute ?? 0, second: parts.second ?? 0
        )
    }

    private static func day(_ parts: Parts) -> String {
        pad(parts.year, 4) + "-" + pad(parts.month) + "-" + pad(parts.day)
    }

    private static func time(_ parts: Parts, separator: String) -> String {
        [pad(parts.hour), pad(parts.minute), pad(parts.second)].joined(separator: separator)
    }

    private static func pad(_ value: Int, _ width: Int = 2) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
