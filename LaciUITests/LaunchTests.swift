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
}
