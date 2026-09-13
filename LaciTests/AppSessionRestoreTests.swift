import Foundation
@testable import Laci
import LaciCore
import Testing

/// Real on-disk stores in a throwaway folder: the only way to prove a restore reopens the right
/// file. Nothing here touches the app's own store.
@MainActor
@Suite("Restore through the session")
struct AppSessionRestoreTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    let root: URL
    let storeURL: URL
    let session: AppSession

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "AppSessionRestoreTests-\(UUID().uuidString)")
        storeURL = root.appending(path: "Application Support/Laci.store")
        let suite = "AppSessionRestoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let backupsURL = root.appending(path: "Backups")
        let backups = BackupService(
            storeURL: storeURL, location: { .localFallback(backupsURL) },
            stagingRoot: root.appending(path: "Staging"), defaults: defaults, shopName: "Warung",
            now: { Self.now }
        )
        session = try AppSession(dependencies: .onDisk(at: storeURL), backups: backups)
    }

    func create(_ sku: String) throws {
        try session.dependencies.products.create(Product(
            sku: sku, name: "Item \(sku)", unit: "pcs", cost: 0, price: 1000, tracksStock: true, updatedAt: Self.now
        ))
    }

    func skus() throws -> [String] {
        try session.dependencies.products.all(includeArchived: false).map(\.sku)
    }

    @Test("Restoring brings back the backed-up rows, rebuilds the dependencies and keeps the printer")
    func restoreReopensTheBackedUpStore() async throws {
        try create("A")
        #expect(await session.backups.backupNow())
        try create("B")
        #expect(try skus() == ["A", "B"])
        let printer = session.dependencies.printer
        let archive = try #require(session.backups.archives.first)

        #expect(await session.restore(from: archive))

        #expect(session.generation == 1)
        #expect(session.restoreNotice == .succeeded(name: archive.name))
        #expect(session.dependencies.printer === printer)
        #expect(try skus() == ["A"])
        #expect(session.backups.hasPreRestoreCopy)
        // The new store is live: a write after the restore lands in it.
        try create("C")
        #expect(try skus() == ["A", "C"])
    }

    @Test("A backup from another schema is refused and the store is untouched")
    func incompatibleBackupIsRefused() async throws {
        try create("A")
        #expect(await session.backups.backupNow())
        let archive = try #require(session.backups.archives.first)
        let other = BackupArchive(
            url: archive.url, name: archive.name,
            manifest: BackupManifest(
                createdAt: Self.now, schemaVersion: "9.0.0", appVersion: "1", build: "1", shopName: "Warung",
                files: archive.manifest.files
            )
        )
        #expect(await !session.restore(from: other))
        #expect(session.restoreNotice == .failed(.incompatibleSchema(found: "9.0.0")))
        #expect(session.generation == 0)
        #expect(try skus() == ["A"])
    }

    @Test("A backup missing its store file is refused before the live files move")
    func missingFileIsRefused() async throws {
        try create("A")
        #expect(await session.backups.backupNow())
        let archive = try #require(session.backups.archives.first)
        try FileManager.default.removeItem(at: archive.url.appending(path: "Laci.store"))
        #expect(await !session.restore(from: archive))
        guard case .failed(.restoreFailed) = session.restoreNotice else {
            Issue.record("expected restoreFailed, got \(String(describing: session.restoreNotice))")
            return
        }
        #expect(session.generation == 0)
        #expect(!session.backups.hasPreRestoreCopy)
        #expect(try skus() == ["A"])
    }
}
