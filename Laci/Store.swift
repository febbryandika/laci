import Foundation
import LaciCore
import os
import SwiftData

/// Schema V1 is the only stage until the first change after TestFlight; every later schema gets a
/// `VersionedSchema`, a `MigrationStage` here, and a test that migrates a copy of a real store file.
enum LaciMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum Store {
    /// The one store file, stated rather than inferred so the backup copies exactly what the
    /// container opens. It is the path SwiftData already used for the configuration named "Laci".
    static let storeURL = URL.applicationSupportDirectory.appending(path: "Laci.store")

    /// SPEC §15. The trade-off, stated: the store is encrypted from boot until the first unlock and
    /// readable from then until the next reboot, including while the screen is locked.
    /// - Why not `.complete`: the store would become unreadable every time the iPad auto-locks. A
    ///   write in flight would fail and the charging-time backup (§5.3), which runs locked, could
    ///   not read the file. For a POS a failed write is a lost sale.
    /// - What it costs: someone who takes an iPad that has been unlocked since its last reboot, and
    ///   can get past the lock screen by other means, can read the sales. Rebooting closes that.
    /// - What it does not do: let the app run before the first unlock. Nothing opens this file
    ///   between a reboot and the first passcode, so a rebooted iPad with a passcode needs that
    ///   passcode once before it can sell. An iPad with no passcode has no such protection at all.
    static let fileProtection = FileProtectionType.completeUntilFirstUserAuthentication

    /// One store, no CloudKit container (SPEC §4, §5.3).
    static func container(inMemory: Bool = false) throws -> ModelContainer {
        guard inMemory else { return try container(at: storeURL) }
        let schema = Schema(versionedSchema: SchemaV1.self)
        // In-memory stores get a unique name so two of them in one process never share rows.
        let configuration = ModelConfiguration(
            UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: LaciMigrationPlan.self, configurations: [configuration])
    }

    /// The store at `url`, opened under the migration plan. `cloudKitDatabase: .none` is explicit
    /// because this initializer defaults to `.automatic`, and SPEC §5.3 rules a sync engine out.
    static func container(at url: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration("Laci", schema: schema, url: url, cloudKitDatabase: .none)
        applyFileProtection(to: url)
        let container = try ModelContainer(
            for: schema, migrationPlan: LaciMigrationPlan.self, configurations: [configuration]
        )
        applyFileProtection(to: url)
        return container
    }

    /// `ModelConfiguration` has no protection option, so it is set on the files. Before opening:
    /// the folder, which the journal files inherit from, and whatever a restore moved in. After
    /// opening: the files SQLite just created. A failure is logged and never stops the app, since
    /// this is the class iOS gives app files anyway and selling matters more than restating it.
    private static func applyFileProtection(to url: URL) {
        let targets = [
            url.deletingLastPathComponent(), url,
            url.deletingLastPathComponent().appending(path: url.lastPathComponent + "-wal"),
            url.deletingLastPathComponent().appending(path: url.lastPathComponent + "-shm"),
        ]
        for target in targets where FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
            do {
                try FileManager.default.setAttributes(
                    [.protectionKey: fileProtection], ofItemAtPath: target.path(percentEncoded: false)
                )
            } catch {
                Log.store.error("file protection not set: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
