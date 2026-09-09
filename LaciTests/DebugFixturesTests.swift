import Foundation
@testable import Laci
import Testing

@MainActor
@Suite("Debug fixture loader")
struct DebugFixturesTests {
    @Test("The bundled warung-200 catalogue loads into an empty store with nothing rejected")
    func loadsCleanly() throws {
        let dependencies = try Dependencies.inMemory()
        let load = try DebugFixtures.loadWarung200(into: dependencies)
        #expect(load.rejected == 0)
        #expect(load.updated == 0)
        #expect(load.added >= 190)
    }

    @Test("Loading the fixture twice updates every row and adds none")
    func loadsIdempotently() throws {
        let dependencies = try Dependencies.inMemory()
        let first = try DebugFixtures.loadWarung200(into: dependencies)
        let second = try DebugFixtures.loadWarung200(into: dependencies)
        #expect(second.added == 0)
        #expect(second.rejected == 0)
        #expect(second.updated == first.added)
    }
}
