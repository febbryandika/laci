import Foundation
import LaciCore
import Observation
import os
import SwiftData

/// Where archives go: the app's iCloud Documents container, or in DEBUG builds a local folder
/// when there is none, so the simulator and CI can walk the flow. Release never falls back.
nonisolated enum BackupLocation: Hashable, Sendable {
    case iCloud(URL)
    case localFallback(URL)

    var url: URL {
        switch self {
        case let .iCloud(url), let .localFallback(url): url
        }
    }

    var isLocalFallback: Bool {
        if case .localFallback = self {
            true
        } else {
            false
        }
    }
}

/// "Backup now" and the scheduled backup (SPEC §5.3). Runs on the main actor because the only
/// writer to the store is the main-context `Transactor`, so no write is in flight while the
/// files are copied. This is a file copy, never a sync engine.
@MainActor
@Observable
final class BackupService {
    enum Status: Hashable {
        case idle
        case running
        case finished(Date)
        case failed(BackupError)
    }

    private(set) var status: Status = .idle
    private(set) var lastBackupAt: Date?
    private(set) var archives: [BackupArchive] = []
    private(set) var location: BackupLocation?
    var automaticEnabled: Bool {
        didSet {
            BackupSettings.save(automaticEnabled: automaticEnabled, in: defaults)
            onAutomaticChanged?(automaticEnabled)
        }
    }

    /// The scheduler hooks in here; the service itself never schedules anything.
    var onAutomaticChanged: ((Bool) -> Void)?

    let storeURL: URL
    let stagingRoot: URL
    private let resolveLocation: @Sendable () -> BackupLocation?
    private let files: BackupFileOperations
    private let defaults: UserDefaults
    private let appVersion: String
    private let build: String
    private let shopName: String
    private let timeZone: TimeZone
    private let now: () -> Date
    private let log = Logger(subsystem: "id.laci", category: "backup")

    init(
        storeURL: URL, location: @escaping @Sendable () -> BackupLocation?,
        stagingRoot: URL = URL.applicationSupportDirectory.appending(path: "BackupStaging"),
        files: BackupFileOperations = .live, defaults: UserDefaults = .standard, bundle: Bundle = .main,
        shopName: String = ShopDefaults.shopName, timeZone: TimeZone = ShopDefaults.timeZone,
        now: @escaping () -> Date = { Date() }
    ) {
        self.storeURL = storeURL
        self.stagingRoot = stagingRoot
        resolveLocation = location
        self.files = files
        self.defaults = defaults
        appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        self.shopName = shopName
        self.timeZone = timeZone
        self.now = now
        automaticEnabled = BackupSettings.automaticEnabled(in: defaults)
        lastBackupAt = BackupSettings.lastBackupAt(in: defaults)
    }

    /// The live container. Resolving the ubiquity URL can take a moment the first time, so it is
    /// done off the main actor by the caller.
    nonisolated static func liveLocation() -> BackupLocation? {
        if let url = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            return .iCloud(url.appending(path: "Documents"))
        }
        #if DEBUG
            return .localFallback(URL.applicationSupportDirectory.appending(path: "LocalBackups"))
        #else
            return nil
        #endif
    }

    // MARK: Backing up

    /// One archive, the seven newest kept. Returns whether an archive was written; a failed prune
    /// after a written archive is reported but still counts as a backup.
    @discardableResult
    func backupNow() async -> Bool {
        guard status != .running else { return false }
        status = .running
        guard let archiver = await resolveArchiver() else {
            status = .failed(.iCloudUnavailable)
            return false
        }
        let startedAt = now()
        let name = "Laci-" + ISODate.compact(startedAt, timeZone: timeZone)
        do {
            let url = try archiver.archive(named: name) { files in
                BackupManifest(
                    createdAt: startedAt, schemaVersion: Self.schemaVersion, appVersion: appVersion, build: build,
                    shopName: shopName, files: files
                )
            }
            log.info("backup written \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("backup failed: \(String(describing: error), privacy: .public)")
            status = .failed(error)
            return false
        }
        lastBackupAt = startedAt
        BackupSettings.save(lastBackupAt: startedAt, in: defaults)
        do {
            try archiver.prune(keeping: BackupArchiver.keep)
            status = .finished(startedAt)
        } catch {
            log.error("prune failed: \(String(describing: error), privacy: .public)")
            status = .failed(error)
        }
        archives = archiver.list()
        return true
    }

    func refreshArchives() async {
        guard let archiver = await resolveArchiver() else {
            archives = []
            return
        }
        archives = archiver.list()
    }

    nonisolated static var schemaVersion: String {
        let version = SchemaV1.versionIdentifier
        return "\(version.major).\(version.minor).\(version.patch)"
    }

    private func resolveArchiver() async -> BackupArchiver? {
        let resolve = resolveLocation
        let resolved = await Task.detached { resolve() }.value
        location = resolved
        guard let resolved else { return nil }
        return BackupArchiver(files: files, storeURL: storeURL, containerURL: resolved.url, stagingRoot: stagingRoot)
    }
}
