import Foundation
@testable import Laci
import Testing

/// A throwaway tree: a fake store with its sidecars, a "container", and a staging folder.
@MainActor
struct BackupSandbox {
    static let jakarta = TimeZone(identifier: "Asia/Jakarta")!

    let root: URL
    let storeURL: URL
    let containerURL: URL
    let stagingRoot: URL
    let defaults: UserDefaults

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "BackupServiceTests-\(UUID().uuidString)")
        storeURL = root.appending(path: "Application Support/Laci.store")
        containerURL = root.appending(path: "iCloud/Documents")
        stagingRoot = root.appending(path: "Application Support/BackupStaging")
        let supportURL = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        let suite = "BackupServiceTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        try write("store bytes", to: storeURL)
        try write("wal bytes!", to: sidecar("wal"))
        try write("shm", to: sidecar("shm"))
    }

    func sidecar(_ kind: String) -> URL {
        storeURL.deletingLastPathComponent().appending(path: "Laci.store-\(kind)")
    }

    func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    func service(
        files: BackupFileOperations = .live, location: BackupLocation? = nil, now: @escaping () -> Date = { Date() }
    ) -> BackupService {
        let location = location ?? .iCloud(containerURL)
        return BackupService(
            storeURL: storeURL, location: { location }, stagingRoot: stagingRoot, files: files, defaults: defaults,
            shopName: "Warung Uji", timeZone: Self.jakarta, now: now
        )
    }

    func unavailableService() -> BackupService {
        BackupService(
            storeURL: storeURL, location: { nil }, stagingRoot: stagingRoot, defaults: defaults,
            shopName: "Warung Uji", timeZone: Self.jakarta
        )
    }

    var backupsURL: URL {
        containerURL.appending(path: "Backups")
    }

    func archiveFolders() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: backupsURL.path(percentEncoded: false)) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func contents(of folder: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            result[file.lastPathComponent] = try Data(contentsOf: file)
        }
        return result
    }
}

/// A fixed clock that the tests advance by hand.
@MainActor
final class BackupClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000) // 15:00 WIB, 15 Jan 2027

    func advance(seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

@MainActor
@Suite("Backup service")
struct BackupServiceTests {
    let sandbox: BackupSandbox
    let clock = BackupClock()

    init() throws {
        sandbox = try BackupSandbox()
    }

    func service(files: BackupFileOperations = .live) -> BackupService {
        let clock = clock
        return sandbox.service(files: files, now: { clock.now })
    }

    @Test("An archive holds the store, both sidecars and a manifest, under a timestamped name")
    func archiveContainsStoreFilesAndManifest() async throws {
        let service = service()
        #expect(await service.backupNow())
        let folders = try sandbox.archiveFolders()
        #expect(folders.map(\.lastPathComponent) == ["Laci-20270115-150000.lacibackup"])
        let files = try sandbox.contents(of: #require(folders.first))
        #expect(files["Laci.store"] == Data("store bytes".utf8))
        #expect(files["Laci.store-wal"] == Data("wal bytes!".utf8))
        #expect(files["Laci.store-shm"] == Data("shm".utf8))
        #expect(files["manifest.json"] != nil)
        #expect(service.status == .finished(clock.now))
        #expect(service.archives.map(\.name) == ["Laci-20270115-150000"])
    }

    @Test("The manifest records the schema, the shop and every file's size")
    func manifestRecordsSchemaShopAndSizes() async throws {
        let service = service()
        #expect(await service.backupNow())
        let archive = try #require(service.archives.first)
        #expect(archive.manifest.schemaVersion == "1.0.0")
        #expect(archive.manifest.shopName == "Warung Uji")
        #expect(archive.manifest.createdAt == clock.now)
        #expect(archive.manifest.formatVersion == 1)
        #expect(archive.manifest.files.map(\.name) == ["Laci.store", "Laci.store-wal", "Laci.store-shm"])
        #expect(archive.manifest.files.map(\.byteCount) == [11, 10, 3])
        #expect(archive.byteCount == 24)
    }

    @Test("The last backup instant is recorded in defaults and on the service")
    func lastBackupAtRecorded() async {
        let service = service()
        #expect(service.lastBackupAt == nil)
        #expect(await service.backupNow())
        #expect(service.lastBackupAt == clock.now)
        #expect(BackupSettings.lastBackupAt(in: sandbox.defaults) == clock.now)
    }

    @Test("Only the seven newest archives are kept")
    func keepsSevenNewest() async throws {
        let service = service()
        for _ in 0 ..< 9 {
            #expect(await service.backupNow())
            clock.advance(seconds: 60)
        }
        let names = try sandbox.archiveFolders().map(\.lastPathComponent)
        #expect(names.count == 7)
        #expect(names.first == "Laci-20270115-150200.lacibackup")
        #expect(names.last == "Laci-20270115-150800.lacibackup")
        #expect(service.archives.count == 7)
        #expect(service.archives.first?.name == "Laci-20270115-150800")
    }

    @Test("Two backups in one second get distinct names")
    func sameSecondNames() async throws {
        let service = service()
        #expect(await service.backupNow())
        #expect(await service.backupNow())
        let names = try sandbox.archiveFolders().map(\.lastPathComponent)
        #expect(names == ["Laci-20270115-150000-2.lacibackup", "Laci-20270115-150000.lacibackup"])
    }

    @Test("Without a container nothing is written and the failure is typed")
    func unavailableContainerFails() async throws {
        let service = sandbox.unavailableService()
        #expect(await !service.backupNow())
        #expect(service.status == .failed(.iCloudUnavailable))
        #expect(service.lastBackupAt == nil)
        #expect(try sandbox.archiveFolders().isEmpty)
    }

    @Test("A failure mid-copy leaves the previous archive byte-identical and adds no partial one")
    func failureMidCopyLeavesPreviousArchiveIntact() async throws {
        #expect(await service().backupNow())
        let before = try sandbox.contents(of: #require(sandbox.archiveFolders().first))
        clock.advance(seconds: 60)

        var failing = BackupFileOperations.live
        failing.copyItem = { source, target in
            if source.lastPathComponent == "Laci.store-wal" {
                throw CocoaError(.fileWriteUnknown)
            }
            try FileManager.default.copyItem(at: source, to: target)
        }
        let service = service(files: failing)
        #expect(await !service.backupNow())
        guard case .failed(.copyFailed) = service.status else {
            Issue.record("expected copyFailed, got \(service.status)")
            return
        }
        let folders = try sandbox.archiveFolders()
        #expect(folders.map(\.lastPathComponent) == ["Laci-20270115-150000.lacibackup"])
        #expect(try sandbox.contents(of: #require(folders.first)) == before)
        // The failed run did not move the last-backup instant past the first run's.
        #expect(service.lastBackupAt == clock.now.addingTimeInterval(-60))
    }

    @Test("A failed prune is reported, but the new archive stays and counts as a backup")
    func pruneFailureIsReportedButArchiveKept() async throws {
        for _ in 0 ..< 7 {
            #expect(await service().backupNow())
            clock.advance(seconds: 60)
        }
        var failing = BackupFileOperations.live
        failing.removeItem = { _ in throw CocoaError(.fileWriteNoPermission) }
        let service = service(files: failing)
        #expect(await service.backupNow())
        guard case .failed(.pruneFailed) = service.status else {
            Issue.record("expected pruneFailed, got \(service.status)")
            return
        }
        #expect(service.lastBackupAt == clock.now)
        #expect(try sandbox.archiveFolders().count == 8)
    }

    @Test("A store without sidecars is archived alone")
    func missingWalIsSkipped() async throws {
        try FileManager.default.removeItem(at: sandbox.sidecar("wal"))
        try FileManager.default.removeItem(at: sandbox.sidecar("shm"))
        let service = service()
        #expect(await service.backupNow())
        let files = try sandbox.contents(of: #require(sandbox.archiveFolders().first))
        #expect(Set(files.keys) == ["Laci.store", "manifest.json"])
        #expect(service.archives.first?.manifest.files.map(\.name) == ["Laci.store"])
    }

    @Test("A missing store file is a failure, not an empty archive")
    func missingStoreFails() async throws {
        try FileManager.default.removeItem(at: sandbox.storeURL)
        let service = service()
        #expect(await !service.backupNow())
        #expect(try sandbox.archiveFolders().isEmpty)
    }

    @Test("Listing reads manifests, newest first, and skips a folder without one")
    func listReadsManifests() async throws {
        let service = service()
        #expect(await service.backupNow())
        clock.advance(seconds: 60)
        #expect(await service.backupNow())
        let stray = sandbox.backupsURL.appending(path: "Laci-99999999-000000.lacibackup")
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        await service.refreshArchives()
        #expect(service.archives.map(\.name) == ["Laci-20270115-150100", "Laci-20270115-150000"])
    }

    @Test("Interrupted staging folders are swept on the next run")
    func staleStagingSwept() async throws {
        let stale = sandbox.stagingRoot.appending(path: "leftover")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        #expect(await service().backupNow())
        #expect(!FileManager.default.fileExists(atPath: stale.path(percentEncoded: false)))
    }

    @Test("Switching automatic backup on or off is persisted and reported")
    func automaticToggle() {
        let service = service()
        var reported: [Bool] = []
        service.onAutomaticChanged = { reported.append($0) }
        service.automaticEnabled = true
        service.automaticEnabled = false
        #expect(reported == [true, false])
        #expect(BackupSettings.automaticEnabled(in: sandbox.defaults) == false)
    }

    // MARK: Restoring

    @Test("A restore swaps the archived files in and keeps the live ones as a pre-restore copy")
    func restoreSwapsFilesAndKeepsPreRestoreCopy() async throws {
        let service = service()
        #expect(await service.backupNow())
        try sandbox.write("newer store", to: sandbox.storeURL)
        try sandbox.write("newer wal", to: sandbox.sidecar("wal"))
        let archive = try #require(service.archives.first)

        let staged = try service.stage(archive)
        #expect(staged.lastPathComponent == "Laci.store")
        #expect(try Data(contentsOf: staged) == Data("store bytes".utf8))
        try service.swapIn(stagedStore: staged)

        #expect(try Data(contentsOf: sandbox.storeURL) == Data("store bytes".utf8))
        #expect(try Data(contentsOf: sandbox.sidecar("wal")) == Data("wal bytes!".utf8))
        #expect(try Data(contentsOf: sandbox.sidecar("shm")) == Data("shm".utf8))
        let aside = BackupArchiver.preRestoreURL(for: sandbox.storeURL)
        #expect(try Data(contentsOf: aside) == Data("newer store".utf8))
        let walAside = BackupArchiver.preRestoreURL(for: sandbox.sidecar("wal"))
        #expect(try Data(contentsOf: walAside) == Data("newer wal".utf8))
        #expect(service.hasPreRestoreCopy)
        #expect(!FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path(percentEncoded: false)))
    }

    @Test("A backup from another schema version is refused before any file moves")
    func restoreRefusesOtherSchemaVersion() {
        let manifest = BackupManifest(
            createdAt: clock.now, schemaVersion: "2.0.0", appVersion: "1", build: "1", shopName: "Warung Uji",
            files: []
        )
        #expect(throws: BackupError.incompatibleSchema(found: "2.0.0")) {
            try service().validate(manifest)
        }
        let current = BackupManifest(
            createdAt: clock.now, schemaVersion: BackupService.schemaVersion, appVersion: "1", build: "1",
            shopName: "Warung Uji", files: []
        )
        #expect(throws: Never.self) {
            try service().validate(current)
        }
    }

    @Test("A rollback drops the swapped-in files and puts the live ones back")
    func rollbackRestoresLiveFiles() async throws {
        let service = service()
        #expect(await service.backupNow())
        try sandbox.write("newer store", to: sandbox.storeURL)
        try FileManager.default.removeItem(at: sandbox.sidecar("shm"))
        let archive = try #require(service.archives.first)
        try service.swapIn(stagedStore: service.stage(archive))
        #expect(FileManager.default.fileExists(atPath: sandbox.sidecar("shm").path(percentEncoded: false)))

        try service.rollbackSwap()
        #expect(try Data(contentsOf: sandbox.storeURL) == Data("newer store".utf8))
        #expect(!FileManager.default.fileExists(atPath: sandbox.sidecar("shm").path(percentEncoded: false)))
        #expect(!service.hasPreRestoreCopy)
    }

    @Test("The next successful backup removes the pre-restore copy")
    func nextBackupRemovesPreRestoreCopy() async throws {
        let service = service()
        #expect(await service.backupNow())
        let archive = try #require(service.archives.first)
        try service.swapIn(stagedStore: service.stage(archive))
        #expect(service.hasPreRestoreCopy)
        clock.advance(seconds: 60)
        #expect(await service.backupNow())
        #expect(!service.hasPreRestoreCopy)
    }

    @Test("An archive whose bytes are still in iCloud is reported, not half-restored")
    func notDownloadedIsReported() async throws {
        let service = service()
        #expect(await service.backupNow())
        let archive = try #require(service.archives.first)
        var pending = BackupFileOperations.live
        pending.isDownloaded = { $0.lastPathComponent != "Laci.store-wal" }
        let waiting = self.service(files: pending)
        #expect(throws: BackupError.notDownloaded) {
            try waiting.stage(archive)
        }
    }
}
