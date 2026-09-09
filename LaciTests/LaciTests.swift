import Foundation
@testable import Laci
import Testing

@Suite("Laci app target")
struct LaciAppTests {
    @Test("Unit tests run hosted inside the Laci app")
    func runsHostedInsideTheApp() {
        #expect(Bundle.main.bundleIdentifier == "id.Laci")
    }
}
