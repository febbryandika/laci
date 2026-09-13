import XCTest

/// SPEC §3.3: count first, then reveal, and a discrepancy over the threshold needs a note.
final class CloseOutFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCountFirstThenRevealThenSave() {
        let app = UITestApp.launch()
        ringUpFixtureSale(app)
        openCloseOut(app, openingFloat: "0", counted: "3500")
        let expected = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Kas seharusnya'")).firstMatch
        XCTAssertFalse(expected.exists)
        tap(app.buttons["CloseOutView.confirm"], "confirm")
        let reveal = element(app, "CloseOutView.reveal")
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        reveal.tap()
        scrollTo(app, expected)
        let save = app.buttons["CloseOutView.save"]
        scrollTo(app, save)
        save.tap()
        XCTAssertTrue(element(app, "CloseOutDetailView.attribution").waitForExistence(timeout: 5))
    }

    @MainActor
    func testDiscrepancyOverThresholdNeedsANote() {
        let app = UITestApp.launch()
        ringUpFixtureSale(app)
        // Rp 10.000 counted against Rp 3.500 expected: over the Rp 5.000 threshold.
        openCloseOut(app, openingFloat: "0", counted: "10000")
        tap(app.buttons["CloseOutView.confirm"], "confirm")
        let save = app.buttons["CloseOutView.save"]
        scrollTo(app, save)
        save.tap()
        XCTAssertTrue(app.staticTexts["Catatan wajib diisi"].waitForExistence(timeout: 5))
        let note = app.textFields["Catatan"]
        scrollTo(app, note)
        note.tap()
        note.typeText("Uang lebih dari kemarin")
        scrollTo(app, save)
        save.tap()
        XCTAssertTrue(element(app, "CloseOutDetailView.attribution").waitForExistence(timeout: 5))
    }
}
