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

    /// The simulator has no camera, so the sheet must land on the manual-entry state (SPEC §9:
    /// never a black rectangle). A camera permission alert, if one appears, is allowed.
    @MainActor
    func testScannerSheetShowsManualEntryWithoutCamera() {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Camera permission") { alert in
            let allow = alert.buttons.element(boundBy: alert.buttons.count - 1)
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        app.launch()
        let scan = app.buttons["SellView.scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.tap()
        XCTAssertTrue(app.navigationBars["Pindai"].waitForExistence(timeout: 5))
        // Interruption monitors run on the next interaction.
        app.navigationBars["Pindai"].tap()
        XCTAssertTrue(app.textFields["ScannerSheet.manualEntry"].waitForExistence(timeout: 10))
    }

    /// Manual entry of an unknown code opens "create SKU with this barcode" prefilled, and saving
    /// puts the new product in the cart (SPEC §3.1.2). A random code keeps the persisted store fresh.
    @MainActor
    func testUnknownCodeFromManualEntryCreatesProductIntoCart() {
        let app = XCUIApplication()
        app.launch()
        let code = "UI-\(Int.random(in: 100_000 ... 999_999))"
        app.buttons["SellView.scan"].tap()
        let entry = app.textFields["ScannerSheet.manualEntry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
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
        let code = "UI-\(Int.random(in: 100_000 ... 999_999))"
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
