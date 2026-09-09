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
    /// One store, no CloudKit container (SPEC §4, §5.3). File protection is not set here: iOS
    /// defaults app files to `.completeUntilFirstUserAuthentication`, which is exactly the policy
    /// SPEC §15 wants for a counter iPad that must resume selling after a reboot.
    static func container(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        // In-memory stores get a unique name so two of them in one process never share rows.
        let configuration = ModelConfiguration(
            inMemory ? UUID().uuidString : "Laci", schema: schema, isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: LaciMigrationPlan.self, configurations: [configuration])
    }
}
