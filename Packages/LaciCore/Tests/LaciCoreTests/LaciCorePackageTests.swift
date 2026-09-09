import LaciCore
import Testing

@Suite("LaciCore package")
struct LaciCorePackageTests {
    @Test("Module builds and links under Swift 6 strict concurrency")
    func packageMarkerIsReachable() {
        #expect(LaciCorePackage.name == "LaciCore")
    }
}
