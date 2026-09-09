import LaciMoney
import Testing

@Suite("LaciMoney package")
struct LaciMoneyPackageTests {
    @Test("Module builds and links under Swift 6 strict concurrency")
    func packageMarkerIsReachable() {
        #expect(LaciMoneyPackage.name == "LaciMoney")
    }
}
