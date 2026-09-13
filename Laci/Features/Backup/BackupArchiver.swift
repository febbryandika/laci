import Foundation

/// Writes, lists and prunes archives (SPEC §5.3). An archive is a folder holding the store file,
/// its `-wal` and `-shm` sidecars when present, and a manifest. It is assembled in a staging
/// directory outside the container and moved in with one rename, so an interruption leaves
/// staging garbage and never a half-written archive next to a good one.
nonisolated struct BackupArchiver: Sendable {
    static let keep = 7
    static let archiveExtension = "lacibackup"
    static let backupsFolder = "Backups"

    let files: BackupFileOperations
    let storeURL: URL
    /// The container's Documents folder.
    let containerURL: URL
    let stagingRoot: URL

    var backupsURL: URL {
        containerURL.appending(path: Self.backupsFolder)
    }

    /// The store and the SQLite sidecars SwiftData keeps beside it; all three travel together.
    static func companionURLs(of store: URL) -> [URL] {
        let folder = store.deletingLastPathComponent()
        let name = store.lastPathComponent
        return [store, folder.appending(path: name + "-wal"), folder.appending(path: name + "-shm")]
    }

    // MARK: Writing

    func archive(
        named name: String, manifest: ([BackupManifest.File]) -> BackupManifest
    ) throws(BackupError) -> URL {
        let staging = stagingRoot.appending(path: UUID().uuidString)
        try step { try files.createDirectory(staging) }
        var copied: [BackupManifest.File] = []
        for source in Self.companionURLs(of: storeURL) where files.fileExists(source) {
            let target = staging.appending(path: source.lastPathComponent)
            try step {
                try files.copyItem(source, target)
                let size = try files.fileSize(target)
                copied.append(BackupManifest.File(name: source.lastPathComponent, byteCount: size))
            }
        }
        guard copied.contains(where: { $0.name == storeURL.lastPathComponent }) else {
            throw .copyFailed("store file missing at \(storeURL.lastPathComponent)")
        }
        try step {
            try files.write(manifest(copied).encoded(), staging.appending(path: BackupManifest.fileName))
            try files.createDirectory(backupsURL)
        }
        let destination = try uniqueDestination(for: name)
        try step { try files.moveItem(staging, destination) }
        sweepStaging(except: staging)
        return destination
    }

    /// Two backups in the same second get distinct names rather than a failed rename.
    private func uniqueDestination(for name: String) throws(BackupError) -> URL {
        var candidate = backupsURL.appending(path: name).appendingPathExtension(Self.archiveExtension)
        var suffix = 2
        while files.fileExists(candidate) {
            candidate = backupsURL.appending(path: "\(name)-\(suffix)").appendingPathExtension(Self.archiveExtension)
            suffix += 1
        }
        return candidate
    }

    /// Leftovers of an interrupted run; best effort, never an error.
    private func sweepStaging(except keep: URL) {
        guard let entries = try? files.contentsOfDirectory(stagingRoot) else { return }
        for entry in entries where entry.lastPathComponent != keep.lastPathComponent {
            try? files.removeItem(entry)
        }
    }

    /// Removes every archive beyond the `keeping` newest. Names embed the timestamp, so name
    /// order is time order and no file date is read.
    func prune(keeping: Int) throws(BackupError) {
        let names = archiveURLs().sorted { $0.lastPathComponent > $1.lastPathComponent }
        for stale in names.dropFirst(keeping) {
            do {
                try files.removeItem(stale)
            } catch {
                throw .pruneFailed("\(stale.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: Reading

    func list() -> [BackupArchive] {
        archiveURLs().compactMap { url in
            guard let data = try? files.read(url.appending(path: BackupManifest.fileName)),
                  let manifest = try? BackupManifest.decode(data) else { return nil }
            return BackupArchive(url: url, name: url.deletingPathExtension().lastPathComponent, manifest: manifest)
        }
        .sorted { $0.name > $1.name }
    }

    private func archiveURLs() -> [URL] {
        ((try? files.contentsOfDirectory(backupsURL)) ?? []).filter { $0.pathExtension == Self.archiveExtension }
    }

    // MARK: Restoring

    static let preRestoreSuffix = ".pre-restore"

    static func preRestoreURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appending(path: url.lastPathComponent + preRestoreSuffix)
    }

    /// The archive's store files copied into a local staging folder, each checked to be on this
    /// device first. Returns the staged store's URL.
    func stage(_ archive: BackupArchive) throws(BackupError) -> URL {
        let folder = stagingRoot.appending(path: "restore-\(UUID().uuidString)")
        try restoreStep { try files.createDirectory(folder) }
        for file in archive.manifest.files {
            let source = archive.url.appending(path: file.name)
            guard files.fileExists(source) else { throw .restoreFailed("\(file.name) tidak ada di cadangan") }
            guard try restoreStep({ try files.isDownloaded(source) }) else { throw .notDownloaded }
            try restoreStep { try files.copyItem(source, folder.appending(path: file.name)) }
        }
        return folder.appending(path: storeURL.lastPathComponent)
    }

    /// Renames the live set aside as `.pre-restore` and moves the staged set into its place. The
    /// live `-wal` goes aside too, so nothing of the old store is replayed onto the restored one.
    func swapIn(stagedStore: URL) throws(BackupError) {
        try removePreRestoreCopies()
        for live in Self.companionURLs(of: storeURL) where files.fileExists(live) {
            try restoreStep { try files.moveItem(live, Self.preRestoreURL(for: live)) }
        }
        let folder = storeURL.deletingLastPathComponent()
        for staged in Self.companionURLs(of: stagedStore) where files.fileExists(staged) {
            try restoreStep { try files.moveItem(staged, folder.appending(path: staged.lastPathComponent)) }
        }
        try? files.removeItem(stagedStore.deletingLastPathComponent())
    }

    /// Undoes `swapIn`: drops whatever was moved in and puts the `.pre-restore` set back.
    func rollbackSwap() throws(BackupError) {
        for live in Self.companionURLs(of: storeURL) {
            let aside = Self.preRestoreURL(for: live)
            if files.fileExists(live) {
                try restoreStep { try files.removeItem(live) }
            }
            if files.fileExists(aside) {
                try restoreStep { try files.moveItem(aside, live) }
            }
        }
    }

    var hasPreRestoreCopy: Bool {
        files.fileExists(Self.preRestoreURL(for: storeURL))
    }

    /// The safety copy is kept until the next successful backup, or the next restore.
    func removePreRestoreCopies() throws(BackupError) {
        for live in Self.companionURLs(of: storeURL) {
            let aside = Self.preRestoreURL(for: live)
            if files.fileExists(aside) {
                try restoreStep { try files.removeItem(aside) }
            }
        }
    }

    private func restoreStep<T>(_ body: () throws -> T) throws(BackupError) -> T {
        do {
            return try body()
        } catch {
            throw .restoreFailed(error.localizedDescription)
        }
    }

    private func step<T>(_ body: () throws -> T) throws(BackupError) -> T {
        do {
            return try body()
        } catch {
            throw .copyFailed(error.localizedDescription)
        }
    }
}
