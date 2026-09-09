import Foundation

/// The shop's cutover rule (SPEC §4): a sale at 01:00 belongs to the previous trading day. Applied
/// once, at commit, and stored on `Sale.tradingDay`; never recomputed on read.
public struct TradingDay: Hashable, Sendable {
    public let cutoverHour: Int

    public init(cutoverHour: Int) {
        precondition((0 ... 23).contains(cutoverHour), "cutoverHour must be an hour of the day, got \(cutoverHour)")
        self.cutoverHour = cutoverHour
    }

    /// 00:00 of the trading day in the shop's zone, the join key for close-out. Calendar
    /// arithmetic rather than seconds so the day boundary stays right in a zone with DST.
    public func bucket(for date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        guard calendar.component(.hour, from: date) < cutoverHour else { return start }
        return calendar.date(byAdding: .day, value: -1, to: start) ?? start
    }

    /// The trading day after `day` (a bucket from `bucket(for:timeZone:)`), for the close-out
    /// sequence: the day after the last close-out is the next one that must be closed.
    public func next(after day: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(byAdding: .day, value: 1, to: day) ?? day
    }
}
