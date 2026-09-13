import XCTest

/// SPEC §9: at AX5 the checkout button is still hittable, and on an iPad the three panes have
/// become two. The collapse is the assertion that matters.
final class AccessibilityLayoutTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCheckoutIsHittableAtAX5AndPanesCollapse() {
        let app = UITestApp.launch(UITestApp.Options(contentSize: UITestApp.ax5))
        scan(app, code: UITestApp.fixtureBarcode)
        XCTAssertTrue(app.buttons["SellView.line.W001"].waitForExistence(timeout: 5))
        let pay = app.buttons["SellView.pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 5))
        XCTAssertTrue(pay.isHittable)
        XCTAssertTrue(element(app, "SellView.cartPane").exists)
        XCTAssertFalse(element(app, "SellView.cataloguePane").exists, "the catalogue pane folds away at AX3")
        if UITestApp.isPad {
            XCTAssertTrue(element(app, "SellView.tenderPane").exists, "two panes remain on an iPad")
        } else {
            XCTAssertFalse(element(app, "SellView.tenderPane").exists, "the keypad is a sheet on an iPhone")
        }
    }

    @MainActor
    func testThreePanesAtAReadingSizeOnIPad() throws {
        try XCTSkipUnless(UITestApp.isPad, "three panes are an iPad layout")
        let app = UITestApp.launch()
        XCTAssertTrue(element(app, "SellView.cataloguePane").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "SellView.cartPane").exists)
        XCTAssertTrue(element(app, "SellView.tenderPane").exists)
        XCTAssertTrue(app.buttons["SellView.catalogue.W001"].exists)
        // The ⌘ shortcut buttons are for the keyboard and the ⌘ overlay, not for VoiceOver.
        XCTAssertFalse(app.buttons["Cari produk"].exists)
    }

    @MainActor
    func testCloseOutConfirmIsHittableAtAX5() {
        let app = UITestApp.launch(UITestApp.Options(contentSize: UITestApp.ax5))
        openCloseOut(app, openingFloat: "0", counted: "0")
        let confirm = app.buttons["CloseOutView.confirm"]
        scrollTo(app, confirm)
        XCTAssertTrue(confirm.isHittable)
    }
}
