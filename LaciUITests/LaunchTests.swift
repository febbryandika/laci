import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesToSellScreen() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.textFields["SellView.search"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHistoryIsReachableFromSell() {
        let app = XCUIApplication()
        app.launch()
        let history = app.buttons["SellView.history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        history.tap()
        XCTAssertTrue(app.navigationBars["Riwayat"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCloseOutIsReachableFromSell() {
        let app = XCUIApplication()
        app.launch()
        let closeOut = app.buttons["SellView.closeOut"]
        XCTAssertTrue(closeOut.waitForExistence(timeout: 5))
        closeOut.tap()
        XCTAssertTrue(app.navigationBars["Tutup kas"].waitForExistence(timeout: 5))
    }
}
