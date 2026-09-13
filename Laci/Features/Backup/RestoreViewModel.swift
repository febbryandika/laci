import Foundation
import Observation

/// The confirmation gate (SPEC §5.3): the shop name typed exactly, then a destructive button,
/// then a dialog. The name is the one on the receipt, so a stranger at the counter cannot guess
/// it from the screen and a slip of the thumb cannot pass it.
@MainActor
@Observable
final class RestoreViewModel {
    let archive: BackupArchive
    let expectedName: String
    var typedName = ""
    private(set) var isRestoring = false

    init(archive: BackupArchive, expectedName: String = ShopDefaults.shopName) {
        self.archive = archive
        self.expectedName = expectedName
    }

    var canConfirm: Bool {
        typedName.trimmingCharacters(in: .whitespaces) == expectedName && !isRestoring
    }

    /// The one sentence that says what is lost. The date is formatted here, in the shop's locale,
    /// so the sentence carries a string the catalog substitutes as-is.
    var warning: LocalizedStringResource {
        let since = archive.createdAt.formatted(DateFormat.dateTime)
        return "Semua penjualan, stok, dan tutup kas setelah \(since) akan hilang dan tidak bisa dikembalikan."
    }

    @discardableResult
    func confirm(session: AppSession) async -> Bool {
        guard canConfirm else { return false }
        isRestoring = true
        defer { isRestoring = false }
        return await session.restore(from: archive)
    }
}
