import Foundation
@testable import Laci
import Testing

@MainActor
@Suite("Restore confirmation")
struct RestoreViewModelTests {
    let archive = BackupArchive(
        url: URL(filePath: "/tmp/Backups/Laci-20270115-150000.lacibackup"), name: "Laci-20270115-150000",
        manifest: BackupManifest(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000), schemaVersion: "1.0.0", appVersion: "1.0",
            build: "7", shopName: "Warung", files: [.init(name: "Laci.store", byteCount: 10)]
        )
    )

    @Test("The button stays disabled until the shop name is typed exactly", arguments: [
        ("", false), ("warung", false), ("Warun", false), ("Warungg", false), ("Warung", true), (" Warung ", true),
    ])
    func confirmDisabledUntilExactShopName(typed: String, enabled: Bool) {
        let viewModel = RestoreViewModel(archive: archive, expectedName: "Warung")
        viewModel.typedName = typed
        #expect(viewModel.canConfirm == enabled)
    }

    @Test("Confirming with the wrong name does nothing to the session")
    func confirmRefusedWhenNameMismatch() async throws {
        let session = try AppSession.inMemory()
        let viewModel = RestoreViewModel(archive: archive, expectedName: "Warung")
        viewModel.typedName = "warung"
        #expect(await !viewModel.confirm(session: session))
        #expect(session.generation == 0)
        #expect(session.restoreNotice == nil)
    }

    @Test("The warning names the backup's date in the shop's zone")
    func warningNamesTheBackupDate() {
        let viewModel = RestoreViewModel(archive: archive, expectedName: "Warung")
        let warning = localized(viewModel.warning)
        #expect(warning.hasPrefix("Semua penjualan, stok, dan tutup kas setelah "))
        #expect(warning.hasSuffix(" akan hilang dan tidak bisa dikembalikan."))
        #expect(warning.contains("2027"))
        #expect(warning.contains("15."))
        // The date is the shop's whatever the UI language: the English sentence carries the same one.
        let english = localized(viewModel.warning, in: "en")
        #expect(english.contains("15."))
        #expect(!english.hasPrefix("Semua"))
    }

    @Test("The expected name defaults to the shop's")
    func expectedNameIsShopName() {
        #expect(RestoreViewModel(archive: archive).expectedName == ShopDefaults.shopName)
    }
}
