import Foundation
@testable import Laci
import Testing

@Suite("Export settings")
struct ExportSettingsTests {
    let defaults: UserDefaults

    init() throws {
        let suite = "ExportSettingsTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("The delimiter is a comma until the semicolon toggle is switched on")
    func defaultIsComma() {
        #expect(ExportSettings.semicolonDelimiter(in: defaults) == false)
        #expect(ExportSettings.delimiter(in: defaults) == ",")
    }

    @Test("The toggle round-trips and selects the semicolon")
    func toggleRoundTrips() {
        ExportSettings.save(semicolonDelimiter: true, in: defaults)
        #expect(ExportSettings.semicolonDelimiter(in: defaults))
        #expect(ExportSettings.delimiter(in: defaults) == ";")
        ExportSettings.save(semicolonDelimiter: false, in: defaults)
        #expect(ExportSettings.delimiter(in: defaults) == ",")
    }
}
