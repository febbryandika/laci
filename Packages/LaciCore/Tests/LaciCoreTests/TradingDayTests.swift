import Foundation
import LaciCore
import Testing

/// Every expectation is built in an explicit zone, never `TimeZone.current`: the dev machine runs
/// WIB and CI runs UTC, and the bucket must not care.
@Suite("Trading-day bucketing")
struct TradingDayTests {
    static let jakarta = TimeZone(identifier: "Asia/Jakarta")!
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    static func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, in zone: TimeZone
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return try #require(calendar.date(from: components))
    }

    @Test("Before the cutover belongs to the previous day, at and after it to the same day", arguments: [
        (1, 59, 9), (2, 0, 10), (23, 59, 10), (0, 0, 9),
    ])
    func cutoverAtTwo(hour: Int, minute: Int, expectedDay: Int) throws {
        let instant = try Self.date(2026, 9, 10, hour, minute, in: Self.jakarta)
        let expected = try Self.date(2026, 9, expectedDay, in: Self.jakarta)
        #expect(TradingDay(cutoverHour: 2).bucket(for: instant, timeZone: Self.jakarta) == expected)
    }

    @Test("A midnight cutover keeps midnight on the same day")
    func midnightCutover() throws {
        let instant = try Self.date(2026, 9, 10, 0, 0, in: Self.jakarta)
        let expected = try Self.date(2026, 9, 10, in: Self.jakarta)
        #expect(TradingDay(cutoverHour: 0).bucket(for: instant, timeZone: Self.jakarta) == expected)
    }

    @Test("The same instant buckets to each shop zone's own start of day, so a changed device zone cannot move it")
    func explicitZoneWins() throws {
        // 23:30 WIB on the 9th is 01:30 JST on the 10th.
        let instant = try Self.date(2026, 9, 9, 23, 30, in: Self.jakarta)
        let policy = TradingDay(cutoverHour: 0)
        let wib = policy.bucket(for: instant, timeZone: Self.jakarta)
        let jst = policy.bucket(for: instant, timeZone: Self.tokyo)
        let expectedWIB = try Self.date(2026, 9, 9, in: Self.jakarta)
        let expectedJST = try Self.date(2026, 9, 10, in: Self.tokyo)
        #expect(wib == expectedWIB)
        #expect(jst == expectedJST)
        #expect(wib != jst)
    }
}
