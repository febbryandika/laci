import Foundation
import LaciCore
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

    /// One store, no CloudKit container (SPEC §4, §5.3). File protection is not set here: iOS
    /// defaults app files to `.completeUntilFirstUserAuthentication`, which is exactly the policy
    /// SPEC §15 wants for a counter iPad that must resume selling after a reboot.
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
        return try ModelContainer(for: schema, migrationPlan: LaciMigrationPlan.self, configurations: [configuration])
    }
}
