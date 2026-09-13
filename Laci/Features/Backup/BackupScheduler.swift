import BackgroundTasks
import Foundation
import os

/// The charging-time backup (SPEC §5.3): one `BGProcessingTask`, registered at launch and
/// submitted only while automatic backup is on. There is no restore here and never will be; a
/// restore is a decision a person makes on the restore screen (SPEC §5.3).
@MainActor
enum BackupScheduler {
    static let identifier = "id.laci.backup"
    private static let log = Logger(subsystem: "id.laci", category: "backup")

    /// Must run before the app finishes launching. The handler is queued on main, so the
    /// non-Sendable `BGTask` never leaves the main actor.
    static func register(service: BackupService) {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated { handle(task, service: service) }
        }
        if !registered {
            // The identifier is not in BGTaskSchedulerPermittedIdentifiers yet: the Xcode step in
            // the Phase 10 PR. Backups still run by hand from Settings.
            log.error("background backup not registered: \(identifier, privacy: .public) is not permitted")
        }
    }

    private static func handle(_ task: BGTask, service: BackupService) {
        let work = Task { @MainActor in
            let succeeded = await service.runScheduled()
            task.setTaskCompleted(success: succeeded)
            schedule(enabled: service.automaticEnabled)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// Submits the next run while charging, or withdraws it when the owner switches automatic
    /// backup off. Safe to call on every backgrounding; a duplicate submission replaces the last.
    static func schedule(enabled: Bool) {
        guard enabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            return
        }
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresExternalPower = true
        // The archive lands in the container; iCloud uploads it whenever it can.
        request.requiresNetworkConnectivity = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.error("background backup not scheduled: \(String(describing: error), privacy: .public)")
        }
    }
}
