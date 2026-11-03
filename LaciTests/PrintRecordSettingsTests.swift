import Foundation
@testable import Laci
import Testing

@Suite("Print record settings")
struct PrintRecordSettingsTests {
    let defaults: UserDefaults

    init() throws {
        let suite = "PrintRecordSettingsTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("Nothing is recorded until a print finishes")
    func empty() {
        #expect(PrintRecordSettings.last(in: defaults) == nil)
    }

    @Test("Both outcomes round-trip, including a transport reason and a missing duration", arguments: [
        PrintRecord(outcome: .printed, duration: .milliseconds(1200), printedAt: Date(timeIntervalSince1970: 1)),
        PrintRecord(outcome: .failed(.transport("timeout")), duration: nil, printedAt: Date(timeIntervalSince1970: 2)),
    ])
    func roundTrip(record: PrintRecord) {
        PrintRecordSettings.save(record, in: defaults)
        #expect(PrintRecordSettings.last(in: defaults) == record)
    }
}
