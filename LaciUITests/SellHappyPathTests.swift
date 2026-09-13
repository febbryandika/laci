import XCTest

/// SPEC §11: scan → cart → cash → change → history, on a store seeded with the real catalogue.
final class SellHappyPathTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testScanCartCashChangeHistory() {
        let app = UITestApp.launch()
        scan(app, code: UITestApp.fixtureBarcode)
        XCTAssertTrue(app.buttons["SellView.line.W001"].waitForExistence(timeout: 5))
        openTender(app)
        // Rp 3.500 paid with Rp 5.000: the change is announced as an amount.
        let change = app.staticTexts["Tender.change"]
        tap(app.buttons["Tender.chip.5000"], "chip") { change.exists }
        XCTAssertTrue(change.label.contains("1.500"), change.label)
        let newSale = app.buttons["TenderView.newSale"]
        tap(newSale, "TenderView.newSale") { !newSale.exists }
        XCTAssertTrue(app.navigationBars["Bayar"].waitForNonExistence(timeout: 5))
        // No printer in the UI-test store, so the sale is saved and the reprint row stays (SPEC §7.3).
        XCTAssertTrue(app.buttons["SellView.reprint"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["SellView.line.W001"].exists)

        push(app, "SellView.history", title: "Riwayat")
        tap(app.staticTexts["#1"], "#1") { app.navigationBars["#1"].exists }
        // Reprintable forever (SPEC §7.3): the button is the last row of the detail form.
        let reprint = app.buttons["SaleDetailView.reprint"]
        scrollTo(app, reprint)
        XCTAssertTrue(reprint.exists)
    }

    @MainActor
    func testKeypadTypesTheTender() {
        let app = UITestApp.launch()
        scan(app, code: UITestApp.fixtureBarcode)
        XCTAssertTrue(app.buttons["SellView.line.W001"].waitForExistence(timeout: 5))
        openTender(app)
        let tendered = app.textFields["Tender.tendered"]
        for (index, key) in ["1", "0", "0", "0", "0"].enumerated() {
            let expected = String("10000".prefix(index + 1))
            tap(app.buttons["Tender.key.\(key)"], key) { (tendered.value as? String) == expected }
        }
        XCTAssertEqual(tendered.value as? String, "10000")
        let change = app.staticTexts["Tender.change"]
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        XCTAssertTrue(change.label.contains("6.500"), change.label)
        let pay = app.buttons[UITestApp.isPad ? "SellView.pay" : "TenderView.pay"]
        XCTAssertTrue(pay.isEnabled)
        let newSale = app.buttons["TenderView.newSale"]
        tap(pay, "pay") { newSale.exists }
    }

    @MainActor
    func testReturnInSearchAddsTheTopMatch() {
        let app = UITestApp.launch()
        let search = app.textFields["SellView.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Indomie Goreng\n")
        XCTAssertTrue(app.buttons["SellView.line.W001"].waitForExistence(timeout: 5))
    }
}
