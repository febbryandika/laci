import Foundation
@testable import Laci
import Testing

@Suite("Backup settings")
struct BackupSettingsTests {
    let defaults: UserDefaults

    init() throws {
        let suite = "BackupSettingsTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("Automatic backup is off and there is no last backup until one runs")
    func nothingUntilFirstRun() {
        #expect(BackupSettings.automaticEnabled(in: defaults) == false)
        #expect(BackupSettings.lastBackupAt(in: defaults) == nil)
    }

    @Test("Both values round-trip")
    func roundTrip() {
        BackupSettings.save(automaticEnabled: true, in: defaults)
        #expect(BackupSettings.automaticEnabled(in: defaults))
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        BackupSettings.save(lastBackupAt: instant, in: defaults)
        #expect(BackupSettings.lastBackupAt(in: defaults) == instant)
    }
}
