import XCTest

/// SPEC §9: the device language picks the UI copy and nothing else. A Japanese iPad with a
/// Japanese locale still shows and announces the shop's rupiah with Indonesian grouping.
final class LocalizationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testJapaneseUIKeepsIndonesianMoney() {
        let app = UITestApp.launch(UITestApp.Options(language: .japanese))
        XCTAssertTrue(app.navigationBars["販売"].waitForExistence(timeout: 5))
        scan(app, code: UITestApp.fixtureBarcode, language: .japanese)
        XCTAssertTrue(app.buttons["SellView.line.W001"].waitForExistence(timeout: 5))
        openTender(app, language: .japanese)
        // Rp 3.500 paid with Rp 5.000 under ja_JP: a device-locale formatter would say "1,500".
        let change = app.staticTexts["Tender.change"]
        tap(app.buttons["Tender.chip.5000"], "chip") { change.exists }
        XCTAssertTrue(change.label.contains("1.500"), change.label)
        XCTAssertFalse(change.label.contains("1,500"), change.label)
        XCTAssertTrue(change.label.hasSuffix("ルピア"), change.label)
    }

    @MainActor
    func testEnglishUIKeepsIndonesianMoney() {
        let app = UITestApp.launch(UITestApp.Options(language: .english))
        XCTAssertTrue(app.navigationBars["Sell"].waitForExistence(timeout: 5))
        ringUpFixtureSale(app, language: .english)
        XCTAssertTrue(app.buttons["SellView.reprint"].waitForExistence(timeout: 10))
        push(app, "SellView.history", title: "History")
        // The sale time is the shop's clock in the shop's format: "HH.mm", never "h:mm AM".
        // The row is one element; its label carries the time.
        let rows = app.descendants(matching: .any)
        let shopTime = rows.matching(NSPredicate(format: "label MATCHES %@", ".*\\d{1,2}\\.\\d{2}.*"))
        XCTAssertTrue(shopTime.firstMatch.waitForExistence(timeout: 5))
        let deviceTime = rows.matching(NSPredicate(format: "label CONTAINS ' AM' OR label CONTAINS ' PM'"))
        XCTAssertFalse(deviceTime.firstMatch.exists)
    }

    /// The AX5 assertion of SPEC §9 again, in the language whose strings run longest.
    @MainActor
    func testCheckoutIsHittableAtAX5InJapanese() {
        let app = UITestApp.launch(UITestApp.Options(contentSize: UITestApp.ax5, language: .japanese))
        scan(app, code: UITestApp.fixtureBarcode, language: .japanese)
        XCTAssertTrue(app.buttons["SellView.line.W001"].waitForExistence(timeout: 5))
        let pay = app.buttons["SellView.pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 5))
        XCTAssertTrue(pay.isHittable)
    }
}
