import Foundation
@testable import Laci
import Testing

private let jakarta = TimeZone(identifier: "Asia/Jakarta") ?? .gmt
private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func line(_ offset: TimeInterval, _ message: String) -> LogLine {
    LogLine(date: base.addingTimeInterval(offset), level: "notice", category: "sale", message: message)
}

@Suite("Log report")
struct LogReportTests {
    @Test("The header comes first, then the entries oldest first")
    func headerThenEntries() {
        let text = LogReport.text(
            header: ["Laci 1.0 (1)"], lines: [line(2, "second"), line(1, "first")], timeZone: jakarta
        )
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(rows[0] == "Laci 1.0 (1)")
        #expect(rows[1] == "Entries: 2 of 2")
        #expect(rows[2].isEmpty)
        #expect(rows[3].hasSuffix("[sale] notice: first"))
        #expect(rows[4].hasSuffix("[sale] notice: second"))
    }

    @Test("Only the newest entries up to the limit are kept, and the count says how many there were")
    func limit() {
        let lines = (0 ..< 600).map { line(TimeInterval($0), "entry \($0)") }
        let text = LogReport.text(header: [], lines: lines, timeZone: jakarta)
        #expect(text.contains("Entries: 500 of 600"))
        #expect(!text.contains("entry 99\n"))
        #expect(text.contains("entry 100\n"))
        #expect(text.contains("entry 599\n"))
    }

    @Test("Times are in the shop's zone")
    func shopTime() {
        // 1_800_000_000 is 2027-01-15 08:00:00 UTC, 15:00 in Jakarta.
        let text = LogReport.text(header: [], lines: [line(0, "x")], timeZone: jakarta)
        #expect(text.contains("15:00:00"))
    }

    @Test("The file name is stamped in the shop's zone")
    func fileName() {
        #expect(SupportLog.fileName(at: base, timeZone: jakarta) == "laci-log-20270115-1500.txt")
    }
}
