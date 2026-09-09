import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesToRootView() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["RootView.title"].waitForExistence(timeout: 5))
    }
}
