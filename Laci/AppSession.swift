import Foundation
import Observation

/// What outlives the store: the dependencies built on it, and the backup service that copies it.
/// A restore replaces `dependencies` and bumps `generation`, and the view tree is rebuilt on it.
@MainActor
@Observable
final class AppSession {
    private(set) var dependencies: Dependencies
    private(set) var generation = 0
    let backups: BackupService

    init(dependencies: Dependencies, backups: BackupService) {
        self.dependencies = dependencies
        self.backups = backups
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
