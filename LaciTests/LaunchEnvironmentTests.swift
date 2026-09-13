import Foundation
@testable import Laci
import Testing

@Suite("Launch environment")
struct LaunchEnvironmentTests {
    @Test("Nothing set means the live store, online")
    func nothingSet() {
        let launch = LaunchEnvironment(environment: [:])
        #expect(!launch.isUITesting)
        #expect(!launch.loadsFixture)
        #expect(!launch.isOffline)
    }

    @Test("UI testing loads the fixture unless the empty key is set")
    func uiTesting() {
        let seeded = LaunchEnvironment(environment: [LaunchEnvironment.uiTestingKey: "1"])
        let empty = LaunchEnvironment(environment: [
            LaunchEnvironment.uiTestingKey: "1", LaunchEnvironment.emptyKey: "1",
        ])
        #if DEBUG
            #expect(seeded.isUITesting)
            #expect(seeded.loadsFixture)
            #expect(empty.isUITesting)
            #expect(!empty.loadsFixture)
        #else
            #expect(!seeded.isUITesting)
            #expect(!empty.isUITesting)
        #endif
    }

    @Test("The empty key alone does not switch stores")
    func emptyAlone() {
        let launch = LaunchEnvironment(environment: [LaunchEnvironment.emptyKey: "1"])
        #expect(!launch.isUITesting)
        #expect(!launch.loadsFixture)
    }

    @Test("Offline is its own flag")
    func offline() {
        let launch = LaunchEnvironment(environment: [LaunchEnvironment.offlineKey: "1"])
        #if DEBUG
            #expect(launch.isOffline)
        #else
            #expect(!launch.isOffline)
        #endif
        #expect(!launch.isUITesting)
    }

    @Test("Anything but 1 is off", arguments: ["", "0", "true", "yes"])
    func malformed(raw: String) {
        let launch = LaunchEnvironment(environment: [
            LaunchEnvironment.uiTestingKey: raw, LaunchEnvironment.offlineKey: raw,
        ])
        #expect(!launch.isUITesting)
        #expect(!launch.isOffline)
    }
}
