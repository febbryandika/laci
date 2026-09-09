import Foundation
import LaciCore
import LaciMoney
import SwiftData
import Testing

/// `Decimal` float literals are not exact (`1.11` is 1.1100000000000002048), so every non-integer
/// value in these tests is built from a string.
func dec(_ text: String) throws -> Decimal {
    try #require(Decimal(string: text))
}

func money(_ text: String) throws -> Money {
    try Money(dec(text))
}

/// One in-memory container per test. The configuration name is unique so parallel suites never
/// share a store.
@MainActor
struct TestStore {
    let container: ModelContainer

    init() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
    }
}
