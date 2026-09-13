import Foundation
@testable import Laci
import Testing

@Suite("Scanner settings")
struct ScannerSettingsTests {
    let defaults: UserDefaults

    init() throws {
        let suite = "ScannerSettingsTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("The keyboard wedge is off until switched on")
    func defaultOff() {
        #expect(ScannerSettings.wedgeEnabled(in: defaults) == false)
    }

    @Test("The toggle round-trips")
    func roundTrip() {
        ScannerSettings.save(wedgeEnabled: true, in: defaults)
        #expect(ScannerSettings.wedgeEnabled(in: defaults))
        ScannerSettings.save(wedgeEnabled: false, in: defaults)
        #expect(ScannerSettings.wedgeEnabled(in: defaults) == false)
    }
}
