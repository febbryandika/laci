import XCTest

/// SPEC §15: the app works fully in airplane mode, and that is a test, not a claim. The simulator
/// has no airplane switch, so the launch environment makes every network-shaped read fail the way
/// it does with no connection: no iCloud container, no App Store price.
final class OfflineRunTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSellingAndClosingOutWorkOffline() {
        let app = UITestApp.launch(UITestApp.Options(offline: true))
        ringUpFixtureSale(app)
        openCloseOut(app, openingFloat: "0", counted: "3500")
        tap(app.buttons["CloseOutView.confirm"], "confirm")
        let save = app.buttons["CloseOutView.save"]
        scrollTo(app, save)
        save.tap()
        XCTAssertTrue(element(app, "CloseOutDetailView.attribution").waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        // The two reads that do need a connection fail softly and block nothing.
        push(app, "SellView.settings", title: "Pengaturan")
        let backupNow = app.buttons["SettingsView.backupNow"]
        scrollTo(app, backupNow)
        backupNow.tap()
        let status = app.staticTexts["SettingsView.backupStatus"]
        scrollTo(app, status)
        XCTAssertTrue(status.label.hasPrefix("iCloud tidak tersedia"), status.label)
        let unlock = app.buttons["SettingsView.unlock"]
        scrollTo(app, unlock)
        unlock.tap()
        let priceFailed = app.staticTexts["Harga tidak bisa dimuat. Periksa koneksi internet."]
        XCTAssertTrue(priceFailed.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["PaywallView.restore"].exists)
        XCTAssertTrue(app.staticTexts["PaywallView.staysOpen"].exists)
        app.buttons["PaywallView.close"].tap()
    }

    /// SPEC §3.4: after the trial only checkout is blocked, with the price, restore and the
    /// sentence that the rest stays open.
    @MainActor
    func testExhaustedTrialBlocksCheckoutWithThePaywall() {
        let app = UITestApp.launch(UITestApp.Options(offline: true, trialLimit: 0))
        scan(app, code: UITestApp.fixtureBarcode)
        XCTAssertTrue(app.buttons["SellView.line.W001"].waitForExistence(timeout: 5))
        let paywall = app.navigationBars["Buka Laci"]
        if element(app, "SellView.tenderPane").exists {
            tap(app.buttons["Tender.chip.5000"], "chip") { paywall.exists }
        } else {
            tap(app.buttons["SellView.pay"], "SellView.pay") { paywall.exists }
        }
        XCTAssertTrue(app.staticTexts["PaywallView.staysOpen"].exists)
        XCTAssertTrue(app.buttons["PaywallView.restore"].exists)
        XCTAssertTrue(element(app, "PaywallView.price").exists)
        app.buttons["PaywallView.close"].tap()
        // The cart is untouched: the catalogue and the sale in progress are not held hostage.
        XCTAssertTrue(app.buttons["SellView.line.W001"].waitForExistence(timeout: 5))
    }
}
