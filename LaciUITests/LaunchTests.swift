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

    /// Opens the scan sheet and returns the manual-entry field once the sheet has settled. The
    /// simulator has no camera but does ask for permission on first use, and an interruption
    /// monitor only runs on an interaction, so the wait taps the bar between checks: the alert can
    /// land before or after any single tap.
    @MainActor
    private func openScannerSheet(_ app: XCUIApplication) -> XCUIElement {
        addUIInterruptionMonitor(withDescription: "Camera permission") { alert in
            let allow = alert.buttons.element(boundBy: alert.buttons.count - 1)
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        let scan = app.buttons["SellView.scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.tap()
        let bar = app.navigationBars["Pindai"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let entry = app.textFields["ScannerSheet.manualEntry"]
        for _ in 0 ..< 15 where !entry.exists {
            bar.tap()
            _ = entry.waitForExistence(timeout: 1)
        }
        return entry
    }

    /// The simulator has no camera, so the sheet must land on the manual-entry state (SPEC §9:
    /// never a black rectangle).
    @MainActor
    func testScannerSheetShowsManualEntryWithoutCamera() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(openScannerSheet(app).exists)
    }

    /// Ten digits: not an EAN shape, so it is looked up as-is and is unknown, and digits only, so
    /// the software keyboard CI types on needs no plane switching. Random, so the persisted store
    /// never already owns it.
    private func unknownCode() -> String {
        "77\(Int.random(in: 10_000_000 ... 99_999_999))"
    }

    /// Manual entry of an unknown code opens "create SKU with this barcode" prefilled, and saving
    /// puts the new product in the cart (SPEC §3.1.2).
    @MainActor
    func testUnknownCodeFromManualEntryCreatesProductIntoCart() {
        let app = XCUIApplication()
        app.launch()
        let code = unknownCode()
        let entry = openScannerSheet(app)
        XCTAssertTrue(entry.exists)
        entry.tap()
        entry.typeText(code + "\n")
        XCTAssertTrue(app.navigationBars["Produk baru"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["NewProductView.sku"].value as? String, code)
        let name = app.textFields["NewProductView.name"]
        name.tap()
        name.typeText("Produk Uji")
        let price = app.textFields["NewProductView.price"]
        price.tap()
        price.typeText("2500")
        app.buttons["NewProductView.save"].tap()
        XCTAssertTrue(app.staticTexts["Produk Uji"].waitForExistence(timeout: 5))
    }

    /// The keyboard-wedge path works with the camera sheet closed: with the toggle on, a payload
    /// plus Return typed at the sell screen reaches the same lookup (SPEC §6).
    @MainActor
    func testWedgePayloadOnSellScreenReachesLookup() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["SellView.settings"].tap()
        let toggle = app.switches["SettingsView.wedgeToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String) != "1" {
            toggle.switches.firstMatch.tap()
        }
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.textFields["SellView.wedge"].waitForExistence(timeout: 5))
        let code = unknownCode()
        // No tap: the hidden field is focused by the screen, which is what a wedge relies on.
        app.typeText(code + "\n")
        XCTAssertTrue(app.navigationBars["Produk baru"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["NewProductView.sku"].value as? String, code)
        app.buttons["Batal"].tap()
        // Leave the setting as it was found for the other tests.
        app.buttons["SellView.settings"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.switches.firstMatch.tap()
    }
}
