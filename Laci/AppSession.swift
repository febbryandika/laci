import Foundation
import Observation
import os

enum RestoreNotice: Hashable {
    case succeeded(name: String)
    case failed(BackupError)
}

/// What outlives the store: the dependencies built on it, and the backup service that copies it.
/// A restore replaces `dependencies` and bumps `generation`, and the view tree is rebuilt on it.
@MainActor
@Observable
final class AppSession {
    private(set) var dependencies: Dependencies
    private(set) var generation = 0
    private(set) var restoreNotice: RestoreNotice?
    private(set) var isRestoring = false
    let backups: BackupService
    /// Here and not in `Dependencies`: a restore rebuilds those, and the `Transaction.updates`
    /// listener must outlive the store (SPEC §5.1).
    let unlock: UnlockStore
    private let log = Logger(subsystem: "id.laci", category: "store")

    init(dependencies: Dependencies, backups: BackupService, unlock: UnlockStore = UnlockStore()) {
        self.dependencies = dependencies
        self.backups = backups
        self.unlock = unlock
    }

    /// The destructive restore (SPEC §5.3), in the order that keeps a store open at every step:
    /// refuse another schema; stage a local copy; prove the copy opens under the migration plan;
    /// rename the live files aside and move the copy in; rebuild the dependencies on it. A failure
    /// after the swap puts the live files back. Nothing here is ever scheduled or automatic.
    @discardableResult
    func restore(from archive: BackupArchive) async -> Bool {
        guard !isRestoring else { return false }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try backups.validate(archive.manifest)
            let staged = try backups.stage(archive)
            do {
                _ = try Store.container(at: staged)
            } catch {
                throw BackupError.restoreFailed("cadangan tidak bisa dibuka: \(error.localizedDescription)")
            }
            try backups.swapIn(stagedStore: staged)
            do {
                dependencies = try Dependencies.reopened(at: backups.storeURL, keeping: dependencies.printer)
            } catch {
                log.error("restored store failed to open, rolling back: \(String(describing: error), privacy: .public)")
                try backups.rollbackSwap()
                dependencies = try Dependencies.reopened(at: backups.storeURL, keeping: dependencies.printer)
                throw BackupError.restoreFailed(error.localizedDescription)
            }
            generation += 1
            restoreNotice = .succeeded(name: archive.name)
            log.info("restored \(archive.name, privacy: .public)")
            return true
        } catch let error as BackupError {
            restoreNotice = .failed(error)
            return false
        } catch {
            restoreNotice = .failed(.restoreFailed(error.localizedDescription))
            return false
        }
    }

    func dismissRestoreNotice() {
        restoreNotice = nil
    }

    static func live() -> AppSession {
        AppSession(
            dependencies: .live(),
            backups: BackupService(storeURL: Store.storeURL, location: BackupService.liveLocation)
        )
    }

    /// In-memory dependencies and a backup service pointed at a throwaway folder, for previews.
    static func inMemory() throws -> AppSession {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "laci-preview-\(UUID().uuidString)")
        return try AppSession(
            dependencies: .inMemory(),
            backups: BackupService(
                storeURL: scratch.appending(path: "Laci.store"),
                location: { .localFallback(scratch.appending(path: "Backups")) },
                stagingRoot: scratch.appending(path: "Staging")
            )
        )
    }
}
