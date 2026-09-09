import LaciPrint
import Testing

@Suite("LaciPrint package")
struct LaciPrintPackageTests {
    @Test("Module builds and links under Swift 6 strict concurrency")
    func packageMarkerIsReachable() {
        #expect(LaciPrintPackage.name == "LaciPrint")
    }
}
